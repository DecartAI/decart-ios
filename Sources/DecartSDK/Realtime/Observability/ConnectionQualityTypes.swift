import Foundation

/// Which dimension pulled the verdict down to its current level.
public enum ConnectionQualityLimitingFactor: String, Sendable, Equatable {
	case bandwidth
	case latency
	case loss
	case stall
	case cpu
	case none
}

/// Human-meaningful numbers behind the verdict. `nil` means not-yet-measured.
public struct ConnectionQualityMetrics: Sendable, Equatable {
	/// Round-trip time (ms), or nil until measured.
	public let rttMs: Double?
	/// Steady-state glass-to-glass latency (ms). Only set under `debugQuality` past
	/// warm-up; drives the latency verdict instead of `rttMs` when present.
	public let g2gMs: Double?
	/// Time-to-first-frame (ms). One-shot startup metric; not part of the live verdict.
	public let ttffMs: Double?
	/// Rendered (inbound) frames per second, or nil until measured.
	public let fps: Double?
	/// Fraction (0–1) of our outbound packets the server reports lost, or nil.
	public let packetLoss: Double?
	/// Server's view of upstream jitter (ms), or nil. Observational.
	public let upstreamJitterMs: Double?
	/// End-to-end frame drop ratio (0–1). Only set under `debugQuality`; nil otherwise.
	public let g2gDropRatio: Double?
	/// Estimated available upstream bandwidth (kbps), or nil until measured.
	public let availableUpstreamKbps: Double?

	public init(
		rttMs: Double?,
		g2gMs: Double? = nil,
		ttffMs: Double? = nil,
		fps: Double?,
		packetLoss: Double?,
		upstreamJitterMs: Double? = nil,
		g2gDropRatio: Double? = nil,
		availableUpstreamKbps: Double?
	) {
		self.rttMs = rttMs
		self.g2gMs = g2gMs
		self.ttffMs = ttffMs
		self.fps = fps
		self.packetLoss = packetLoss
		self.upstreamJitterMs = upstreamJitterMs
		self.g2gDropRatio = g2gDropRatio
		self.availableUpstreamKbps = availableUpstreamKbps
	}
}

/// Smoothed verdict on whether the connection is good enough for the realtime
/// pipeline, derived from the WebRTC stats the SDK collects each second.
public struct ConnectionQualityReport: Sendable, Equatable {
	public let quality: ConnectionQuality
	public let limitingFactor: ConnectionQualityLimitingFactor
	/// True while the connection ramps; the verdict is provisional.
	public let warmingUp: Bool
	public let metrics: ConnectionQualityMetrics

	public init(
		quality: ConnectionQuality,
		limitingFactor: ConnectionQualityLimitingFactor,
		warmingUp: Bool,
		metrics: ConnectionQualityMetrics
	) {
		self.quality = quality
		self.limitingFactor = limitingFactor
		self.warmingUp = warmingUp
		self.metrics = metrics
	}
}
