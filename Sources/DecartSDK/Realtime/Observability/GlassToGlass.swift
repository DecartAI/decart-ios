import Foundation

/// Monotonic wall-clock in milliseconds (immune to system clock changes). Used for
/// glass-to-glass stamp/match timing.
func monotonicMs() -> Double {
	Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
}

/// Aggregated glass-to-glass metrics. TTFF (startup) and mid-stream (steady state)
/// are measured separately — they differ by an order of magnitude and cold-start
/// frames must not pollute the steady-state numbers.
public struct G2GMetrics: Sendable, Equatable {
	/// Time-to-first-frame (ms): connect attempt start → first rendered model output. Nil until the first frame.
	public let ttffMs: Double?
	/// Median mid-stream (steady-state) glass-to-glass latency (ms), excluding warm-up. Nil until past warm-up.
	public let medianMs: Double?
	/// p90 mid-stream glass-to-glass latency (ms), or nil until past warm-up.
	public let p90Ms: Double?
	/// Mid-stream latency samples in the window (post-warm-up).
	public let sampleCount: Int
	/// End-to-end frame drop ratio (0–1): seqs stamped but never rendered. Nil until enough outcomes exist.
	public let dropRatio: Double?

	public init(ttffMs: Double?, medianMs: Double?, p90Ms: Double?, sampleCount: Int, dropRatio: Double?) {
		self.ttffMs = ttffMs
		self.medianMs = medianMs
		self.p90Ms = p90Ms
		self.sampleCount = sampleCount
		self.dropRatio = dropRatio
	}
}

/// Matches outgoing stamp times to incoming render times to compute true
/// camera→display latency, and infers end-to-end drops from seqs stamped but never
/// rendered. Ported 1:1 from the JS SDK's `SeqTracker`.
///
/// Thread-safe: `stampNext` runs on the capture/processor queue, `recordInbound` on
/// the renderer queue, and `snapshot` on the stats-poll queue — all serialized by an
/// internal lock, so it is safely `@unchecked Sendable`.
final class SeqTracker: @unchecked Sendable {
	private let lock = NSLock()
	/// Bound on in-flight seqs; a seq that ages out unmatched is an end-to-end drop.
	private static let maxPending = 256
	/// Rolling window for the latency percentiles (≈10s at 30fps).
	private static let latencyWindow = 300
	/// Rolling window of delivered/dropped outcomes for the drop ratio.
	private static let outcomeWindow = 300
	/// Don't report a drop ratio until this many outcomes exist.
	private static let dropMinOutcomes = 30
	/// Discard implausible deltas (clock weirdness, seq wrap collisions).
	private static let maxPlausibleMs: Double = 60_000
	/// After the first frame, ignore this long before counting steady-state samples.
	private static let midStreamWarmupMs: Double = 2_000

	private var stampTimes: [Int: Double] = [:]
	/// Pending seqs in insertion (== time) order; mirrors `stampTimes`' key set.
	private var stampOrder: [Int] = []
	private var latencies: [Double] = []
	/// true = delivered (matched), false = dropped (aged out unmatched).
	private var outcomes: [Bool] = []
	private var nextSeq = 0
	private var startMs: Double?
	private var firstMatchMs: Double?
	private var ttffMs: Double?

	/// Mark the start of a connect attempt; resets measurement state. TTFF is measured from here.
	func markStart(_ nowMs: Double) {
		lock.lock(); defer { lock.unlock() }
		resetLocked()
		startMs = nowMs
	}

	/// Allocate the next seq for an outgoing frame and record its stamp time. Returns the 16-bit seq.
	func stampNext(_ nowMs: Double) -> Int {
		lock.lock(); defer { lock.unlock() }
		let seq = nextSeq & 0xffff
		nextSeq = (nextSeq + 1) & 0xffff
		stampTimes[seq] = nowMs
		stampOrder.append(seq)
		if stampTimes.count > Self.maxPending {
			// Oldest insertion aged out without a match.
			if let oldest = stampOrder.first {
				removePending(oldest)
				// Only a real drop once the stream is live and past warm-up.
				if isPastWarmup(nowMs) { recordOutcome(false) }
			}
		}
		return seq
	}

	/// Match a seq read off an inbound rendered frame. Ignores unknown/duplicate seqs.
	func recordInbound(_ seq: Int, _ nowMs: Double) {
		lock.lock(); defer { lock.unlock() }
		guard let stampedAt = stampTimes[seq] else { return } // unknown, consumed, or evicted
		removePending(seq)
		let g2g = nowMs - stampedAt
		if g2g < 0 || g2g > Self.maxPlausibleMs { return }

		if firstMatchMs == nil {
			// First rendered frame: capture TTFF and discard any older pending stamps
			// so they don't later age out as phantom drops.
			firstMatchMs = nowMs
			if let startMs { ttffMs = nowMs - startMs }
			for pendingSeq in stampOrder {
				guard let stampTime = stampTimes[pendingSeq] else { continue }
				if stampTime < stampedAt { removePending(pendingSeq) } else { break }
			}
		}

		if !isPastWarmup(nowMs) { return } // first frame + warm-up don't pollute steady state
		latencies.append(g2g)
		if latencies.count > Self.latencyWindow { latencies.removeFirst() }
		recordOutcome(true)
	}

	func snapshot() -> G2GMetrics {
		lock.lock(); defer { lock.unlock() }
		let sorted = latencies.sorted()
		let n = sorted.count
		// True median: average the two middle samples on an even count (nearest-rank
		// would bias high and can tip a verdict near a band threshold). p90 stays nearest-rank.
		let medianMs: Double?
		if n == 0 {
			medianMs = nil
		} else if n % 2 == 0 {
			medianMs = ((sorted[n / 2 - 1] + sorted[n / 2]) / 2).rounded()
		} else {
			medianMs = sorted[(n - 1) / 2].rounded()
		}
		let p90Ms: Double? = n == 0 ? nil : sorted[min(n - 1, Int(0.9 * Double(n)))].rounded()

		var dropRatio: Double?
		if outcomes.count >= Self.dropMinOutcomes {
			let dropped = outcomes.reduce(0) { $0 + ($1 ? 0 : 1) }
			dropRatio = Double(dropped) / Double(outcomes.count)
		}
		return G2GMetrics(ttffMs: ttffMs, medianMs: medianMs, p90Ms: p90Ms, sampleCount: n, dropRatio: dropRatio)
	}

	/// Clear measurement state. Keeps `nextSeq` monotonic to avoid stale collisions.
	func reset() {
		lock.lock(); defer { lock.unlock() }
		resetLocked()
	}

	private func resetLocked() {
		stampTimes.removeAll()
		stampOrder.removeAll()
		latencies.removeAll()
		outcomes.removeAll()
		startMs = nil
		firstMatchMs = nil
		ttffMs = nil
	}

	private func removePending(_ seq: Int) {
		stampTimes.removeValue(forKey: seq)
		if let idx = stampOrder.firstIndex(of: seq) { stampOrder.remove(at: idx) }
	}

	private func isPastWarmup(_ nowMs: Double) -> Bool {
		guard let firstMatchMs else { return false }
		return nowMs >= firstMatchMs + Self.midStreamWarmupMs
	}

	private func recordOutcome(_ delivered: Bool) {
		outcomes.append(delivered)
		if outcomes.count > Self.outcomeWindow { outcomes.removeFirst() }
	}
}
