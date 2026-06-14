import Foundation

/// Smooths metrics over a rolling window and applies asymmetric hysteresis so the
/// emitted level doesn't flap. `update()` returns a report only when the level or
/// warm-up state changes; `current()` returns the latest at any time.
///
/// Not `Sendable` — it holds mutable state and is owned/serialized by
/// `ConnectionQualityStatsCollector`. Ported 1:1 from the JS SDK's
/// `ConnectionQualityEvaluator`.
final class ConnectionQualityEvaluator {
	private let thresholds: ConnectionQualityThresholds

	private var rtt: RingBuffer
	private var glassToGlass: RingBuffer
	private var loss: RingBuffer
	private var availableOutgoing: RingBuffer
	private var fps: RingBuffer

	private var sampleCount = 0
	private var currentLevel: ConnectionQuality?
	// Reason for the current verdict; refreshed to the live cause, but held across a
	// recovery lag (bad level still debounced while the latest sample improved).
	private var currentFactor: ConnectionQualityLimitingFactor = .none
	private var candidateLevel: ConnectionQuality?
	private var candidateCount = 0
	private var prevWarmingUp = true
	private var lastReport: ConnectionQualityReport?

	init(thresholds: ConnectionQualityThresholds = .default) {
		self.thresholds = thresholds
		let w = thresholds.windowSamples
		rtt = RingBuffer(capacity: w)
		glassToGlass = RingBuffer(capacity: w)
		loss = RingBuffer(capacity: w)
		availableOutgoing = RingBuffer(capacity: w)
		fps = RingBuffer(capacity: w)
	}

	/// Feed one raw stats sample. Returns a report only when the level or warm-up state changes.
	@discardableResult
	func update(_ raw: QualitySignals) -> ConnectionQualityReport? {
		sampleCount += 1

		rtt.push(raw.rttMs)
		glassToGlass.push(raw.g2gMs)
		loss.push(raw.fractionLost)
		availableOutgoing.push(raw.availableOutgoingKbps)
		fps.push(raw.fps)

		// `ttffMs`/`upstreamJitterMs` (observational) and `g2gDropRatio` (already
		// windowed by the SeqTracker) ride through from `raw` un-resmoothed.
		var smoothed = raw
		smoothed.rttMs = rtt.median()
		smoothed.g2gMs = glassToGlass.median()
		smoothed.fractionLost = loss.median()
		smoothed.availableOutgoingKbps = availableOutgoing.median()
		smoothed.fps = fps.min()

		let warmingUp = sampleCount < thresholds.warmupSamples
		let scored = ConnectionQualityScoring.scoreMetrics(smoothed, thresholds: thresholds, skipBitrate: warmingUp)

		// Warm-up skips bandwidth scoring; when it ends, commit the fully-scored verdict
		// immediately so the first non-warming report is authoritative, rather than
		// holding the optimistic "good" through the downgrade debounce.
		let warmupJustEnded = prevWarmingUp && !warmingUp
		prevWarmingUp = warmingUp

		var changed: Bool
		if warmupJustEnded {
			changed = currentLevel != scored.quality
			currentLevel = scored.quality
			candidateLevel = nil
			candidateCount = 0
		} else {
			changed = applyHysteresis(scored.quality)
		}

		let emitted = currentLevel ?? scored.quality

		// limitingFactor explains why we're at `emitted`: nothing when good; otherwise
		// the current worst dimension — but keep the last committed reason while a bad
		// level is held and the latest sample has already recovered above it.
		if emitted == .good {
			currentFactor = smoothed.qualityLimitationReason == "cpu" ? .cpu : .none
		} else if scored.quality.rank <= emitted.rank {
			currentFactor = scored.limitingFactor
		}

		lastReport = ConnectionQualityReport(
			quality: emitted,
			limitingFactor: currentFactor,
			warmingUp: warmingUp,
			metrics: ConnectionQualityMetrics(
				rttMs: smoothed.rttMs,
				g2gMs: smoothed.g2gMs,
				// ttffMs (one-shot startup), upstreamJitterMs (observational), and
				// g2gDropRatio (already windowed) are surfaced raw, not re-smoothed.
				ttffMs: raw.ttffMs,
				fps: smoothed.fps,
				packetLoss: smoothed.fractionLost,
				upstreamJitterMs: raw.upstreamJitterMs,
				g2gDropRatio: raw.g2gDropRatio,
				availableUpstreamKbps: smoothed.availableOutgoingKbps
			)
		)

		return (changed || warmupJustEnded) ? lastReport : nil
	}

	func current() -> ConnectionQualityReport? {
		lastReport
	}

	func reset() {
		rtt.clear()
		glassToGlass.clear()
		loss.clear()
		availableOutgoing.clear()
		fps.clear()
		sampleCount = 0
		currentLevel = nil
		currentFactor = .none
		candidateLevel = nil
		candidateCount = 0
		prevWarmingUp = true
		lastReport = nil
	}

	/// Returns true if the debounced level changed this tick.
	private func applyHysteresis(_ raw: ConnectionQuality) -> Bool {
		guard let level = currentLevel else {
			currentLevel = raw // first verdict — emit immediately
			candidateLevel = nil
			candidateCount = 0
			return true
		}

		if raw == level {
			candidateLevel = nil
			candidateCount = 0
			return false
		}

		if raw == candidateLevel {
			candidateCount += 1
		} else {
			candidateLevel = raw
			candidateCount = 1
		}

		let isDowngrade = raw.rank < level.rank
		let required = isDowngrade ? thresholds.downgradeConsecutive : thresholds.upgradeConsecutive
		if candidateCount >= required {
			currentLevel = raw
			candidateLevel = nil
			candidateCount = 0
			return true
		}
		return false
	}
}
