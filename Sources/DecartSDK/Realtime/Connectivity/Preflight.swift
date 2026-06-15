import Foundation

/// Map probe metrics to a connectivity quality verdict. Pure.
/// Ported 1:1 from the JS SDK's `classifyConnectivity` (reason strings verbatim).
public func classifyConnectivity(
	metrics: ConnectivityMetrics,
	thresholds: PreflightRttThresholds
) -> ConnectivityReport {
	var reasons: [String] = []
	let quality: ConnectionQuality

	switch metrics.transport {
	case .failed:
		quality = .critical
		reasons.append(
			"Could not establish any WebRTC connectivity (no ICE candidates gathered). Real-time streaming is unlikely to work on this network."
		)
	case .relay:
		quality = .poor
		reasons.append(
			"Direct UDP connectivity could not be confirmed; the session will need a TURN relay, which adds latency and can't be verified without starting a session."
		)
	case .udp:
		if let rtt = metrics.rttMs, rtt > thresholds.marginalMs {
			quality = .poor
			reasons.append(
				"Network round-trip time is high (~\(rtt)ms > \(thresholds.marginalMs)ms); the real-time experience may feel laggy."
			)
		} else if let rtt = metrics.rttMs, rtt > thresholds.goodMs {
			quality = .fair
			reasons.append("Network round-trip time is elevated (~\(rtt)ms > \(thresholds.goodMs)ms).")
		} else {
			quality = .good
		}
	}

	return ConnectivityReport(quality: quality, metrics: metrics, reasons: reasons)
}

/// Classify a deep-probe result. Judges startup (TTFF) and steady-state (mid-stream
/// glass-to-glass) latency separately — both are real experienced latency on
/// different scales — and folds in drops + upstream loss. Falls back to RTT only
/// when neither latency could be measured. Pure. Ported 1:1 from the JS SDK.
public func classifyActiveProbe(
	metrics: ConnectivityMetrics,
	thresholds: ConnectionQualityThresholds = .default
) -> ConnectivityReport {
	if metrics.transport == .failed {
		return ConnectivityReport(
			quality: .critical,
			metrics: metrics,
			reasons: ["Could not establish a realtime session for the deep probe."]
		)
	}

	var reasons: [String] = []
	var dims: [ConnectionQuality] = []

	if let ttffMs = metrics.ttffMs {
		let t = thresholds.ttff
		let q = ConnectionQualityScoring.scoreLowerBetter(ttffMs, good: t.goodMs, fair: t.fairMs, poor: t.poorMs)
		dims.append(q)
		if q != .good {
			reasons.append(
				"Time to first frame is ~\(String(format: "%.1f", ttffMs / 1000))s (good ≤ \(Int(t.goodMs / 1000))s); the session is slow to start."
			)
		}
	}

	if let g2gMs = metrics.g2gMs {
		let g = thresholds.glassToGlass
		let q = ConnectionQualityScoring.scoreLowerBetter(g2gMs, good: g.goodMs, fair: g.fairMs, poor: g.poorMs)
		dims.append(q)
		if q != .good {
			reasons.append(
				"Mid-stream glass-to-glass latency is ~\(Int(g2gMs))ms (good ≤ \(Int(g.goodMs))ms); the real-time experience may feel laggy."
			)
		}
	}

	if metrics.ttffMs == nil, metrics.g2gMs == nil {
		if let rttMs = metrics.rttMs {
			reasons.append(
				"Could not measure glass-to-glass latency during the probe (no marker round-trip); using network RTT instead."
			)
			let r = thresholds.rtt
			dims.append(ConnectionQualityScoring.scoreLowerBetter(Double(rttMs), good: r.goodMs, fair: r.fairMs, poor: r.poorMs))
		} else {
			reasons.append("The probe connected but could not measure latency (no marker round-trip and no RTT sample).")
		}
	}

	if let drop = metrics.g2gDropRatio {
		let d = thresholds.g2gDrop
		let q = ConnectionQualityScoring.scoreLowerBetter(drop, good: d.good, fair: d.fair, poor: d.poor)
		dims.append(q)
		if q != .good {
			reasons.append("End-to-end frame drop ratio is \(String(format: "%.1f", drop * 100))% (good ≤ \(Int(d.good * 100))%).")
		}
	}

	if let loss = metrics.packetLoss {
		let l = thresholds.loss
		let q = ConnectionQualityScoring.scoreLowerBetter(loss, good: l.good, fair: l.fair, poor: l.poor)
		dims.append(q)
		if q != .good {
			reasons.append("Upstream packet loss is \(String(format: "%.1f", loss * 100))% (good ≤ \(Int(l.good * 100))%).")
		}
	}

	// Connected but no usable quality signal — don't claim "good" we never verified.
	if dims.isEmpty {
		return ConnectivityReport(quality: .fair, metrics: metrics, reasons: reasons)
	}

	return ConnectivityReport(quality: ConnectionQualityScoring.worst(dims), metrics: metrics, reasons: reasons)
}

/// SDK-only connectivity preflight — run before `connect(localStream:)` to decide
/// whether to show the realtime integration. Probes public STUN over UDP (no
/// session, no inference) to check whether WebRTC can leave the network over UDP
/// and roughly how laggy the path is. It does not measure throughput — use the
/// in-session connection-quality signal for that.
///
/// Stateless and credential-free: the probe only hits public STUN, so it needs no
/// API key. `DecartClient.checkConnectivity()` forwards here for discoverability.
public enum Preflight {
	/// Check whether the user's network can support a real-time session *before*
	/// connecting. Never throws — degrades to `.critical` / `.failed` on any error.
	///
	/// ```swift
	/// let report = await Preflight.checkConnectivity()
	/// if report.quality == .critical { showFallbackUI(report.reasons) }
	/// ```
	public static func checkConnectivity(options: CheckConnectivityOptions = .init()) async -> ConnectivityReport {
		let thresholds = RealtimeConfig.Preflight.rtt
		if Task.isCancelled {
			return classifyConnectivity(metrics: ConnectivityMetrics(transport: .failed, rttMs: nil), thresholds: thresholds)
		}

		let servers = options.stunServers ?? RealtimeConfig.Preflight.defaultStunServers
		let timeoutMs = options.iceGatherTimeoutMs ?? RealtimeConfig.Preflight.iceGatherTimeoutMs

		// Probe servers in order; return on the first confirmed UDP egress, else
		// keep the best non-UDP result (relay over failed). No servers → failed.
		var best = ConnectivityMetrics(transport: .failed, rttMs: nil)
		for server in servers {
			if Task.isCancelled { break }
			let metrics = await STUNProbe.probe(server: server, timeoutMs: timeoutMs)
			if metrics.transport == .udp {
				best = metrics
				break
			}
			if metrics.transport == .relay, best.transport == .failed {
				best = metrics
			}
		}

		return classifyConnectivity(metrics: best, thresholds: thresholds)
	}
}

public extension DecartClient {
	/// Check whether the network can sustain a realtime session *before* connecting,
	/// so you can gate showing the integration. Never throws.
	///
	/// Default (STUN-only): probes public STUN over UDP — no session, no inference,
	/// no API key required. Opt-in deep probe (`CheckConnectivityOptions(deep: true,
	/// model:)`): briefly opens a real session with a synthetic source, measures
	/// true glass-to-glass latency, then tears it down — accurate, costs a short GPU
	/// session.
	///
	/// ```swift
	/// let report = await client.checkConnectivity()
	/// if report.quality == .critical { showFallbackUI(report.reasons) }
	///
	/// let deep = await client.checkConnectivity(.init(deep: true, model: Models.realtime(.lucy2_1)))
	/// print(deep.metrics.g2gMs ?? -1, deep.metrics.ttffMs ?? -1)
	/// ```
	func checkConnectivity(options: CheckConnectivityOptions = .init()) async -> ConnectivityReport {
		if options.deep {
			guard let model = options.model else {
				return ConnectivityReport(
					quality: .critical,
					metrics: ConnectivityMetrics(transport: .failed, rttMs: nil),
					reasons: ["Deep connectivity probe requires a model (latency is model-specific)."]
				)
			}
			return await runDeepProbe(model: model, durationMs: options.durationMs ?? RealtimeConfig.Preflight.activeDurationMs)
		}
		return await Preflight.checkConnectivity(options: options)
	}

	/// Open a short real session on a synthetic source with glass-to-glass
	/// measurement, wait for samples (or the window), classify, then tear down.
	private func runDeepProbe(model: ModelDefinition, durationMs: Int) async -> ConnectivityReport {
		let tracker = SeqTracker()
		let synthetic = SyntheticVideoSource(width: model.width, height: model.height, fps: model.fps, tracker: tracker)
		var stream = RealtimeMediaStream(videoTrack: synthetic.track, id: .localStream)
		stream.seqTracker = tracker
		synthetic.start()

		let manager: DecartRealtimeManager
		do {
			manager = try createRealtimeManager(options: RealtimeConfiguration(model: model, debugQuality: true))
		} catch {
			synthetic.stop()
			return classifyActiveProbe(metrics: ConnectivityMetrics(transport: .failed, rttMs: nil))
		}

		var established = false
		do {
			_ = try await manager.connect(localStream: stream)
			established = true
			let deadline = Date().addingTimeInterval(Double(durationMs) / 1000)
			while Date() < deadline {
				if Task.isCancelled { break }
				if tracker.snapshot().sampleCount >= RealtimeConfig.Preflight.activeMinSamples { break }
				try await Task.sleep(nanoseconds: 200_000_000)
			}
		} catch {
			DecartLogger.log("deep connectivity probe failed: \(error.localizedDescription)", level: .warning)
		}

		let metrics: ConnectivityMetrics = established
			? activeProbeMetrics(report: manager.getConnectionQuality(), g2g: tracker.snapshot(), isRelayed: manager.isPathRelayed())
			: ConnectivityMetrics(transport: .failed, rttMs: nil)

		await manager.disconnect()
		synthetic.stop()
		return classifyActiveProbe(metrics: metrics)
	}

	private func activeProbeMetrics(report: ConnectionQualityReport?, g2g: G2GMetrics?, isRelayed: Bool?) -> ConnectivityMetrics {
		let m = report?.metrics
		return ConnectivityMetrics(
			transport: isRelayed == true ? .relay : .udp,
			rttMs: m?.rttMs.map { Int($0.rounded()) },
			g2gMs: g2g?.medianMs,
			ttffMs: g2g?.ttffMs,
			g2gDropRatio: g2g?.dropRatio,
			upstreamJitterMs: m?.upstreamJitterMs,
			packetLoss: m?.packetLoss,
			sampleCount: g2g?.sampleCount
		)
	}
}
