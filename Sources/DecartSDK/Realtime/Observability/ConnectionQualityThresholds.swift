import Foundation

/// Thresholds for the derived in-session connection-quality signal
/// (see `ConnectionQualityEvaluator`). Tuned for a camera-up real-time
/// pipeline (~3–3.5 Mbps upstream, model fps ~25–30). All values are tunable
/// so behaviour can change without code edits.
///
/// Mirrors `REALTIME_CONFIG.observability.connectionQuality` in the JS SDK.
public struct ConnectionQualityThresholds: Sendable, Equatable {
	/// Round-trip time bands (ms). Bands widen by `relayExtraMs` on TURN-relayed paths.
	public struct RTT: Sendable, Equatable {
		public let goodMs: Double
		public let fairMs: Double
		public let poorMs: Double
		public let relayExtraMs: Double

		public init(goodMs: Double, fairMs: Double, poorMs: Double, relayExtraMs: Double) {
			self.goodMs = goodMs
			self.fairMs = fairMs
			self.poorMs = poorMs
			self.relayExtraMs = relayExtraMs
		}
	}

	/// Mid-stream (steady-state) true glass-to-glass latency bands (ms) — used for the
	/// latency dimension *instead of* RTT when pixel-marker measurement is on. Already
	/// includes both network legs, so relayExtraMs does not apply. Excludes startup (see `ttff`).
	public struct GlassToGlass: Sendable, Equatable {
		public let goodMs: Double
		public let fairMs: Double
		public let poorMs: Double

		public init(goodMs: Double, fairMs: Double, poorMs: Double) {
			self.goodMs = goodMs
			self.fairMs = fairMs
			self.poorMs = poorMs
		}
	}

	/// Time-to-first-frame bands (ms) — startup latency from connect to the first
	/// rendered model frame. Judged separately from mid-stream latency.
	public struct TTFF: Sendable, Equatable {
		public let goodMs: Double
		public let fairMs: Double
		public let poorMs: Double

		public init(goodMs: Double, fairMs: Double, poorMs: Double) {
			self.goodMs = goodMs
			self.fairMs = fairMs
			self.poorMs = poorMs
		}
	}

	/// Fraction of outbound packets the server reports lost (0...1).
	public struct Loss: Sendable, Equatable {
		public let good: Double
		public let fair: Double
		public let poor: Double

		public init(good: Double, fair: Double, poor: Double) {
			self.good = good
			self.fair = fair
			self.poor = poor
		}
	}

	/// End-to-end frame drop ratio bands (0...1), inferred from the pixel-marker seq stream.
	public struct G2GDrop: Sendable, Equatable {
		public let good: Double
		public let fair: Double
		public let poor: Double

		public init(good: Double, fair: Double, poor: Double) {
			self.good = good
			self.fair = fair
			self.poor = poor
		}
	}

	/// Upstream headroom = available BWE ÷ the intended publish bitrate (`requiredUpstreamKbps`).
	public struct Upstream: Sendable, Equatable {
		public let goodRatio: Double
		public let fairRatio: Double
		public let poorRatio: Double
		public let requiredUpstreamKbps: Double

		public init(goodRatio: Double, fairRatio: Double, poorRatio: Double, requiredUpstreamKbps: Double) {
			self.goodRatio = goodRatio
			self.fairRatio = fairRatio
			self.poorRatio = poorRatio
			self.requiredUpstreamKbps = requiredUpstreamKbps
		}
	}

	/// Rendered (inbound) frames-per-second bands.
	public struct Stall: Sendable, Equatable {
		public let goodFps: Double
		public let fairFps: Double
		public let poorFps: Double

		public init(goodFps: Double, fairFps: Double, poorFps: Double) {
			self.goodFps = goodFps
			self.fairFps = fairFps
			self.poorFps = poorFps
		}
	}

	/// Rolling-window size used to smooth raw per-sample metrics.
	public let windowSamples: Int
	/// Samples to wait before the bitrate dimensions count — the encoder and BWE
	/// ramp for several seconds after connect, so early low bitrate is not a slow
	/// network. RTT/loss/stall start scoring sooner.
	public let warmupSamples: Int
	/// Consecutive worse samples required before the level downgrades.
	public let downgradeConsecutive: Int
	/// Consecutive better samples required before the level upgrades (recover slow).
	public let upgradeConsecutive: Int
	public let rtt: RTT
	public let glassToGlass: GlassToGlass
	public let ttff: TTFF
	public let loss: Loss
	public let g2gDrop: G2GDrop
	public let upstream: Upstream
	public let stall: Stall

	public init(
		windowSamples: Int,
		warmupSamples: Int,
		downgradeConsecutive: Int,
		upgradeConsecutive: Int,
		rtt: RTT,
		glassToGlass: GlassToGlass,
		ttff: TTFF,
		loss: Loss,
		g2gDrop: G2GDrop,
		upstream: Upstream,
		stall: Stall
	) {
		self.windowSamples = windowSamples
		self.warmupSamples = warmupSamples
		self.downgradeConsecutive = downgradeConsecutive
		self.upgradeConsecutive = upgradeConsecutive
		self.rtt = rtt
		self.glassToGlass = glassToGlass
		self.ttff = ttff
		self.loss = loss
		self.g2gDrop = g2gDrop
		self.upstream = upstream
		self.stall = stall
	}

	/// Canonical defaults, matching the JS SDK (`config-realtime.ts`).
	public static let `default` = ConnectionQualityThresholds(
		windowSamples: 5,
		warmupSamples: 8,
		downgradeConsecutive: 5,
		upgradeConsecutive: 5,
		rtt: RTT(goodMs: 150, fairMs: 300, poorMs: 500, relayExtraMs: 100),
		glassToGlass: GlassToGlass(goodMs: 500, fairMs: 900, poorMs: 1500),
		ttff: TTFF(goodMs: 4_000, fairMs: 6_000, poorMs: 10_000),
		loss: Loss(good: 0.02, fair: 0.05, poor: 0.1),
		g2gDrop: G2GDrop(good: 0.02, fair: 0.05, poor: 0.1),
		upstream: Upstream(goodRatio: 1.0, fairRatio: 0.8, poorRatio: 0.5, requiredUpstreamKbps: 3500),
		stall: Stall(goodFps: 20, fairFps: 12, poorFps: 5)
	)
}
