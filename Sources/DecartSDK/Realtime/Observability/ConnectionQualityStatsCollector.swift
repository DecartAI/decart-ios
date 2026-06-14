import Foundation
@preconcurrency import LiveKit

/// Bridges LiveKit's per-track WebRTC statistics into the in-session
/// `ConnectionQualityEvaluator` and emits `ConnectionQualityReport`s.
///
/// LiveKit uses separate publisher/subscriber peer connections, so the signals
/// are split across two tracks: outbound bitrate / RTT / loss / quality-limitation
/// come from the **local** published track; rendered fps / freeze come from the
/// **remote** subscribed track. We enable LiveKit's `set(reportStatistics:)` on
/// both (which refreshes each track's `statistics` ~1 Hz) and poll those snapshots
/// on our own serial-queue timer, merging them into one signal set per tick.
///
/// We poll rather than implement `TrackDelegate.track(_:didUpdateStatistics:…)`:
/// that requirement is `@objc optional` with a `[VideoCodec: TrackStatistics]`
/// parameter that a Swift method can't be `@objc` for, so it can't reliably be the
/// witness LiveKit invokes via optional chaining. Polling `statistics` (a plain
/// public property) is robust and lets us merge both tracks on a single clock.
///
/// All state mutation + evaluation + yield is serialized on a private queue, so the
/// non-Sendable evaluator is single-threaded by construction.
final class ConnectionQualityStatsCollector: @unchecked Sendable {
	let updates: AsyncStream<ConnectionQualityReport>

	private let continuation: AsyncStream<ConnectionQualityReport>.Continuation
	private let queue = DispatchQueue(label: "ai.decart.realtime.connectionQuality")
	private let evaluator: ConnectionQualityEvaluator
	private let pollInterval: DispatchTimeInterval = .milliseconds(1000)
	/// Glass-to-glass tracker (opt-in `debugQuality`); its snapshot is merged into
	/// each sample so measured latency drives the verdict. Nil when off.
	private let seqTracker: SeqTracker?

	private weak var localTrack: Track?
	private weak var remoteTrack: Track?

	private var pollTimer: DispatchSourceTimer?
	// Strong refs to the last-evaluated snapshots, for identity dedup (LiveKit hands
	// out a new TrackStatistics object on each refresh).
	private var lastLocalStats: TrackStatistics?
	private var lastRemoteStats: TrackStatistics?
	private var prevRemoteFreezeCount: UInt?
	private var lastReport: ConnectionQualityReport?
	private var lastIsRelayed: Bool?

	init(thresholds: ConnectionQualityThresholds, seqTracker: SeqTracker? = nil) {
		self.seqTracker = seqTracker
		evaluator = ConnectionQualityEvaluator(thresholds: thresholds)
		let (stream, continuation) = AsyncStream.makeStream(
			of: ConnectionQualityReport.self,
			bufferingPolicy: .bufferingNewest(1)
		)
		updates = stream
		self.continuation = continuation
	}

	func attachLocal(_ track: Track) async {
		queue.sync { localTrack = track }
		await track.set(reportStatistics: true)
		startPollingIfNeeded()
	}

	func attachRemote(_ track: Track) async {
		queue.sync { remoteTrack = track }
		await track.set(reportStatistics: true)
		startPollingIfNeeded()
	}

	func current() -> ConnectionQualityReport? {
		queue.sync { lastReport }
	}

	/// Whether the selected ICE path is TURN-relayed; nil until stats arrive.
	func currentIsRelayed() -> Bool? {
		queue.sync { lastIsRelayed }
	}

	/// Latest glass-to-glass snapshot (only when `debugQuality` is on), or nil.
	func currentGlassToGlass() -> G2GMetrics? {
		seqTracker?.snapshot()
	}

	/// Stop polling, disable LiveKit's stats timers, and finish the stream.
	func stop() {
		let (local, remote) = queue.sync { () -> (Track?, Track?) in
			pollTimer?.cancel()
			pollTimer = nil
			let pair = (localTrack, remoteTrack)
			localTrack = nil
			remoteTrack = nil
			return pair
		}
		if let local { Task { await local.set(reportStatistics: false) } }
		if let remote { Task { await remote.set(reportStatistics: false) } }
		continuation.finish()
	}

	// MARK: - Polling (queue-confined)

	private func startPollingIfNeeded() {
		queue.sync {
			guard pollTimer == nil else { return }
			let timer = DispatchSource.makeTimerSource(queue: queue)
			timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
			timer.setEventHandler { [weak self] in self?.poll() }
			pollTimer = timer
			timer.resume()
		}
	}

	private func poll() {
		let local = localTrack?.statistics
		let remote = remoteTrack?.statistics
		// Skip if neither snapshot changed since last evaluation (LiveKit refreshes at
		// ~1 Hz; identity changes on each refresh) — avoids feeding duplicate samples.
		// When glass-to-glass is on, always evaluate: its snapshot changes between
		// ticks even when the WebRTC stats objects don't.
		if seqTracker == nil, local === lastLocalStats, remote === lastRemoteStats { return }
		lastLocalStats = local
		lastRemoteStats = remote

		let signals = buildSignals(local: local, remote: remote)
		if let report = evaluator.update(signals) {
			lastReport = report
			continuation.yield(report)
		} else {
			lastReport = evaluator.current()
		}
	}

	private func buildSignals(local: TrackStatistics?, remote: TrackStatistics?) -> QualitySignals {
		let localPair = selectedPair(local)
		let remoteVideo = inboundVideo(remote)

		// RTT: prefer the publisher's remote-inbound report, else the selected pair.
		let rttSec = local?.remoteInboundRtpStream.first?.roundTripTime ?? localPair?.currentRoundTripTime
		let rttMs = rttSec.map { $0 * 1000 }

		// fractionLost: standardized 0–1 on Apple platforms (NOT the RFC 3550 ×256
		// value the JS SDK normalizes) — pass through unchanged.
		let fractionLost = local?.remoteInboundRtpStream.first?.fractionLost

		// remote-inbound jitter is the server's view of our uplink; seconds → ms.
		let upstreamJitterMs = local?.remoteInboundRtpStream.first?.jitter.map { $0 * 1000 }

		let availableOutgoingKbps = localPair?.availableOutgoingBitrate.map { $0 / 1000 }

		let fps = remoteVideo?.framesPerSecond

		var freezeDelta: Int?
		if let freeze = remoteVideo?.freezeCount {
			if let prev = prevRemoteFreezeCount {
				// Guard a counter reset (new remote track after reconnect) → no spurious stall.
				freezeDelta = freeze >= prev ? Int(freeze - prev) : 0
			}
			prevRemoteFreezeCount = freeze
		}

		let qualityLimitationReason = outboundVideo(local)?.qualityLimitationReason?.rawValue

		let isRelayed = isRelayedCandidate(local) || isRelayedCandidate(remote)
		lastIsRelayed = isRelayed

		// Merge measured glass-to-glass (opt-in) — drives the latency verdict when present.
		let g2g = seqTracker?.snapshot()

		return QualitySignals(
			rttMs: rttMs,
			g2gMs: g2g?.medianMs,
			ttffMs: g2g?.ttffMs,
			upstreamJitterMs: upstreamJitterMs,
			fractionLost: fractionLost,
			g2gDropRatio: g2g?.dropRatio,
			availableOutgoingKbps: availableOutgoingKbps,
			fps: fps,
			freezeCountDelta: freezeDelta,
			qualityLimitationReason: qualityLimitationReason,
			isRelayed: isRelayed
		)
	}

	private func selectedPair(_ stats: TrackStatistics?) -> IceCandidatePairStatistics? {
		guard let pairs = stats?.iceCandidatePair, !pairs.isEmpty else { return nil }
		return pairs.first(where: { $0.nominated == true })
			?? pairs.first(where: { $0.state == .succeeded })
			?? pairs.first
	}

	private func inboundVideo(_ stats: TrackStatistics?) -> InboundRtpStreamStatistics? {
		stats?.inboundRtpStream.first(where: { $0.kind == "video" }) ?? stats?.inboundRtpStream.first
	}

	private func outboundVideo(_ stats: TrackStatistics?) -> OutboundRtpStreamStatistics? {
		let video = stats?.outboundRtpStream.filter { $0.kind == "video" } ?? []
		// Highest active layer when simulcast is on (sortedByRidIndex is descending).
		return video.sortedByRidIndex().first ?? stats?.outboundRtpStream.first
	}

	private func isRelayedCandidate(_ stats: TrackStatistics?) -> Bool {
		stats?.localIceCandidate?.candidateType == .relay || stats?.remoteIceCandidate?.candidateType == .relay
	}
}
