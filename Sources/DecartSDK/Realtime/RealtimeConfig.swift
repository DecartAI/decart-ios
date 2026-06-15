import Foundation

/// Internal constants for realtime observability + preflight, mirroring the JS
/// SDK's `config-realtime.ts`. Not part of the public contract — callers tune
/// behaviour via `CheckConnectivityOptions` / `RealtimeConfiguration.observability`.
enum RealtimeConfig {
	/// SDK-only preflight (see `Preflight`). Validates WebRTC reachability (does UDP
	/// egress to STUN work / will the path need TURN) and latency via a throwaway
	/// UDP STUN probe — no backend session, no media server.
	enum Preflight {
		/// Public STUN servers used to probe server-reflexive reachability.
		static let defaultStunServers: [STUNServer] = [STUNServer(host: "stun.l.google.com", port: 19302)]
		/// Abort the probe after this long.
		static let iceGatherTimeoutMs: Int = 5_000
		/// RTT bands (ms) for the preflight verdict.
		static let rtt = PreflightRttThresholds(goodMs: 150, marginalMs: 300)
		/// Deep probe: sampling window (must cover TTFF ~4–5s + warm-up ~2s before
		/// steady-state samples accrue); resolves early once `activeMinSamples` exist.
		static let activeDurationMs = 12_000
		static let activeMinSamples = 5
	}

	enum Observability {
		/// Thresholds for the derived in-session connection-quality signal.
		static let connectionQuality = ConnectionQualityThresholds.default
	}
}
