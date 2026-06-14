import Foundation

/// The raw (per-sample) signals the scorer needs, decoupled from LiveKit's stat
/// types so the scoring logic is unit-testable without LiveKit objects. The
/// LiveKit → `QualitySignals` mapping lives in `ConnectionQualityStatsCollector`.
///
/// `fractionLost` is a normalized 0–1 fraction. Unlike the JS SDK — which reads
/// the raw RFC 3550 8-bit value and divides by 256 — LiveKit/WebRTC on Apple
/// platforms reports the standardized `remote-inbound-rtp.fractionLost`, which is
/// already 0–1, so the collector passes it through unchanged.
public struct QualitySignals: Sendable, Equatable {
	public var rttMs: Double?
	/// Mid-stream glass-to-glass latency (ms); drives the latency dimension when present.
	public var g2gMs: Double?
	/// Time-to-first-frame (ms); observational, surfaced not scored live.
	public var ttffMs: Double?
	/// Server's view of upstream jitter (ms); observational, unscored.
	public var upstreamJitterMs: Double?
	public var fractionLost: Double?
	/// End-to-end frame drop ratio (0–1); folds into the stall dimension.
	public var g2gDropRatio: Double?
	public var availableOutgoingKbps: Double?
	public var fps: Double?
	public var freezeCountDelta: Int?
	/// Encoder-reported limitation: "none" | "cpu" | "bandwidth" | "other" (WebRTC spec strings).
	public var qualityLimitationReason: String?
	public var isRelayed: Bool

	public init(
		rttMs: Double? = nil,
		g2gMs: Double? = nil,
		ttffMs: Double? = nil,
		upstreamJitterMs: Double? = nil,
		fractionLost: Double? = nil,
		g2gDropRatio: Double? = nil,
		availableOutgoingKbps: Double? = nil,
		fps: Double? = nil,
		freezeCountDelta: Int? = nil,
		qualityLimitationReason: String? = nil,
		isRelayed: Bool = false
	) {
		self.rttMs = rttMs
		self.g2gMs = g2gMs
		self.ttffMs = ttffMs
		self.upstreamJitterMs = upstreamJitterMs
		self.fractionLost = fractionLost
		self.g2gDropRatio = g2gDropRatio
		self.availableOutgoingKbps = availableOutgoingKbps
		self.fps = fps
		self.freezeCountDelta = freezeCountDelta
		self.qualityLimitationReason = qualityLimitationReason
		self.isRelayed = isRelayed
	}
}

/// Pure scoring functions ported 1:1 from the JS SDK's `connection-quality.ts`.
enum ConnectionQualityScoring {
	static func worst(_ qualities: ConnectionQuality...) -> ConnectionQuality {
		worst(qualities)
	}

	static func worst(_ qualities: [ConnectionQuality]) -> ConnectionQuality {
		qualities.reduce(qualities[0]) { $0.rank <= $1.rank ? $0 : $1 }
	}

	// A nil metric scores "good" — absence of evidence is not evidence of badness.
	static func scoreLowerBetter(_ value: Double?, good: Double, fair: Double, poor: Double) -> ConnectionQuality {
		guard let value else { return .good }
		if value <= good { return .good }
		if value <= fair { return .fair }
		if value <= poor { return .poor }
		return .critical
	}

	static func scoreHigherBetter(_ value: Double?, good: Double, fair: Double, poor: Double) -> ConnectionQuality {
		guard let value else { return .good }
		if value >= good { return .good }
		if value >= fair { return .fair }
		if value >= poor { return .poor }
		return .critical
	}

	/// Score an already-extracted (optionally smoothed) signal set. Pure.
	/// When `skipBitrate` is true (warm-up), the bandwidth dimension is excluded.
	static func scoreMetrics(
		_ signals: QualitySignals,
		thresholds: ConnectionQualityThresholds,
		skipBitrate: Bool = false
	) -> (quality: ConnectionQuality, limitingFactor: ConnectionQualityLimitingFactor) {
		// Prefer measured glass-to-glass — the real experienced latency — when the
		// opt-in pixel-marker measurement is active. It already includes both network
		// legs, so relay headroom doesn't apply. Fall back to RTT otherwise.
		let relayExtra = signals.isRelayed ? thresholds.rtt.relayExtraMs : 0
		let latency: ConnectionQuality
		if let g2gMs = signals.g2gMs {
			latency = scoreLowerBetter(
				g2gMs,
				good: thresholds.glassToGlass.goodMs,
				fair: thresholds.glassToGlass.fairMs,
				poor: thresholds.glassToGlass.poorMs
			)
		} else {
			latency = scoreLowerBetter(
				signals.rttMs,
				good: thresholds.rtt.goodMs + relayExtra,
				fair: thresholds.rtt.fairMs + relayExtra,
				poor: thresholds.rtt.poorMs + relayExtra
			)
		}

		let loss = scoreLowerBetter(
			signals.fractionLost,
			good: thresholds.loss.good,
			fair: thresholds.loss.fair,
			poor: thresholds.loss.poor
		)

		// Upstream only: available BWE ÷ the INTENDED publish bitrate. Dividing by
		// the encoder's adaptive target would mask throttling (it drops with the
		// uplink). Downstream bitrate is intentionally not scored — it's server-chosen.
		var bandwidth: ConnectionQuality = .good
		if !skipBitrate {
			let ratio = signals.availableOutgoingKbps.map { $0 / thresholds.upstream.requiredUpstreamKbps }
			bandwidth = scoreHigherBetter(
				ratio,
				good: thresholds.upstream.goodRatio,
				fair: thresholds.upstream.fairRatio,
				poor: thresholds.upstream.poorRatio
			)
			// Encoder self-reporting a bandwidth limit is a stronger signal than the ratio.
			if signals.qualityLimitationReason == "bandwidth" { bandwidth = worst(bandwidth, .fair) }
		}

		var stall = scoreHigherBetter(
			signals.fps,
			good: thresholds.stall.goodFps,
			fair: thresholds.stall.fairFps,
			poor: thresholds.stall.poorFps
		)
		if let delta = signals.freezeCountDelta, delta > 0 { stall = worst(stall, .fair) }
		// End-to-end frame drops (server backpressure / overload, or transit loss)
		// surface as the same user-visible symptom as a low frame rate.
		let drop = scoreLowerBetter(
			signals.g2gDropRatio,
			good: thresholds.g2gDrop.good,
			fair: thresholds.g2gDrop.fair,
			poor: thresholds.g2gDrop.poor
		)
		stall = worst(stall, drop)

		let quality = worst(bandwidth, latency, loss, stall)

		// Worst network dimension (tie-break bandwidth > loss > latency > stall).
		// "cpu" is informational and only surfaces when the network is otherwise clean.
		let limitingFactor: ConnectionQualityLimitingFactor
		if quality == .good {
			limitingFactor = signals.qualityLimitationReason == "cpu" ? .cpu : .none
		} else if bandwidth == quality {
			limitingFactor = .bandwidth
		} else if loss == quality {
			limitingFactor = .loss
		} else if latency == quality {
			limitingFactor = .latency
		} else {
			limitingFactor = .stall
		}

		return (quality, limitingFactor)
	}
}
