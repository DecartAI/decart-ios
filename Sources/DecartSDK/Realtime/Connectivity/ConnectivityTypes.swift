import Foundation

/// How the probe expects WebRTC to leave this network.
/// - `udp`: direct UDP egress to STUN works.
/// - `relay`: UDP to STUN couldn't be confirmed; a session will need a TURN relay (unverified, SDK-only).
/// - `failed`: no connectivity at all.
public enum ConnectivityTransport: String, Sendable, Equatable {
	case udp
	case relay
	case failed
}

public struct ConnectivityMetrics: Sendable, Equatable {
	public let transport: ConnectivityTransport
	/// Approximate network round-trip time (ms) from the STUN binding round trip
	/// (or the real RTT in deep mode), or nil.
	public let rttMs: Int?
	/// Deep-probe only: measured mid-stream (steady-state) glass-to-glass latency (ms), or nil.
	public let g2gMs: Double?
	/// Deep-probe only: time-to-first-frame (ms) — startup latency to the first rendered model frame, or nil.
	public let ttffMs: Double?
	/// Deep-probe only: end-to-end frame drop ratio (0–1), or nil.
	public let g2gDropRatio: Double?
	/// Deep-probe only: server's view of upstream jitter (ms), or nil.
	public let upstreamJitterMs: Double?
	/// Deep-probe only: server-reported upstream packet loss (0–1), or nil.
	public let packetLoss: Double?
	/// Deep-probe only: number of glass-to-glass samples collected, or nil.
	public let sampleCount: Int?

	public init(
		transport: ConnectivityTransport,
		rttMs: Int?,
		g2gMs: Double? = nil,
		ttffMs: Double? = nil,
		g2gDropRatio: Double? = nil,
		upstreamJitterMs: Double? = nil,
		packetLoss: Double? = nil,
		sampleCount: Int? = nil
	) {
		self.transport = transport
		self.rttMs = rttMs
		self.g2gMs = g2gMs
		self.ttffMs = ttffMs
		self.g2gDropRatio = g2gDropRatio
		self.upstreamJitterMs = upstreamJitterMs
		self.packetLoss = packetLoss
		self.sampleCount = sampleCount
	}
}

public struct ConnectivityReport: Sendable, Equatable {
	/// Pre-connect quality on the same `good → critical` scale as the in-session
	/// signal — you decide what to do with it.
	public let quality: ConnectionQuality
	public let metrics: ConnectivityMetrics
	/// Human-readable explanations for any non-`good` verdict.
	public let reasons: [String]

	public init(quality: ConnectionQuality, metrics: ConnectivityMetrics, reasons: [String]) {
		self.quality = quality
		self.metrics = metrics
		self.reasons = reasons
	}
}

/// RTT bands (ms) for the preflight verdict. Mirrors `REALTIME_CONFIG.preflight.rtt`.
public struct PreflightRttThresholds: Sendable, Equatable {
	public let goodMs: Int
	public let marginalMs: Int

	public init(goodMs: Int, marginalMs: Int) {
		self.goodMs = goodMs
		self.marginalMs = marginalMs
	}
}

/// A STUN endpoint for the preflight probe. The iOS analog of a JS `RTCIceServer`
/// — the native probe only speaks STUN (not TURN), so a host:port is the honest
/// representation.
public struct STUNServer: Sendable, Equatable {
	public let host: String
	public let port: UInt16

	public init(host: String, port: UInt16 = 3478) {
		self.host = host
		self.port = port
	}

	/// Parses a `"stun:host"` or `"stun:host:port"` URL (also accepts `stuns:`).
	/// Returns nil if no host can be extracted.
	public init?(url: String) {
		var rest = url
		for scheme in ["stuns:", "stun:"] where rest.hasPrefix(scheme) {
			rest = String(rest.dropFirst(scheme.count))
			break
		}
		// Strip any query/params (e.g. "?transport=udp").
		if let q = rest.firstIndex(of: "?") { rest = String(rest[..<q]) }
		guard !rest.isEmpty else { return nil }

		if let lastColon = rest.lastIndex(of: ":"),
			let parsedPort = UInt16(rest[rest.index(after: lastColon)...]) {
			let host = String(rest[..<lastColon])
			guard !host.isEmpty else { return nil }
			self.init(host: host, port: parsedPort)
		} else {
			self.init(host: rest)
		}
	}
}

public struct CheckConnectivityOptions: Sendable {
	/// Override the STUN servers used for the probe. Defaults to public STUN.
	public var stunServers: [STUNServer]?
	/// Abort the probe after this long (ms). Defaults to config.
	public var iceGatherTimeoutMs: Int?
	/// Opt-in "deep" probe: instead of the STUN-only network check, briefly open a
	/// real session with a synthetic source, measure true glass-to-glass latency,
	/// then tear it down. Requires `model`. Costs a short GPU session.
	public var deep: Bool
	/// Required when `deep`: the realtime model to probe (latency is model-specific).
	public var model: ModelDefinition?
	/// Deep-probe sampling duration (ms). Defaults to config.
	public var durationMs: Int?

	public init(
		stunServers: [STUNServer]? = nil,
		iceGatherTimeoutMs: Int? = nil,
		deep: Bool = false,
		model: ModelDefinition? = nil,
		durationMs: Int? = nil
	) {
		self.stunServers = stunServers
		self.iceGatherTimeoutMs = iceGatherTimeoutMs
		self.deep = deep
		self.model = model
		self.durationMs = durationMs
	}
}
