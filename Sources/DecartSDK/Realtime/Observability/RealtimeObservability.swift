import Foundation

actor RealtimeObservability {
	typealias TelemetryTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
	typealias ObservabilityForwarder = @Sendable (DecartRealtimeJSONValue) async -> Void

	nonisolated let diagnosticUpdates: AsyncStream<DecartRealtimeDiagnosticEvent>
	nonisolated let statsUpdates: AsyncStream<DecartRealtimeWebRTCStats>

	private let apiKey: String?
	private let model: String
	private let telemetryEnabled: Bool
	private let userAgent: String
	private let telemetryTransport: TelemetryTransport
	private let telemetryURL = URL(string: "https://platform.decart.ai/api/v1/telemetry")!
	private let reportIntervalNanoseconds: UInt64 = 10_000_000_000
	private let maxItemsPerReport = 120

	private let diagnosticContinuation: AsyncStream<DecartRealtimeDiagnosticEvent>.Continuation
	private let statsContinuation: AsyncStream<DecartRealtimeWebRTCStats>.Continuation
	private var telemetryTask: Task<Void, Never>?
	private var sessionId: String?
	private var statsBuffer: [DecartRealtimeWebRTCStats] = []
	private var diagnosticsBuffer: [DecartRealtimeDiagnosticEvent] = []
	private var observabilityForwarder: ObservabilityForwarder?
	private var videoStalled = false
	private var stallStartMs: Int64 = 0
	private var pathObserver: NetworkPathObserver?
	private var connectionBreakdown: ConnectionBreakdownBuffer?
	private var lastSelectedPairSignature: String?
	private var lastIceState: String?
	private var lastCandidatePairStates: [String: String] = [:]
	private var connectionDiagnosticsEnabled = true

	init(
		apiKey: String?,
		model: String,
		telemetryEnabled: Bool,
		telemetryTransport: @escaping TelemetryTransport = { request in
			try await URLSession.shared.data(for: request)
		}
	) {
		self.apiKey = apiKey
		self.model = model
		self.telemetryEnabled = telemetryEnabled && apiKey?.isEmpty == false
		self.userAgent = DecartUserAgent.build()
		self.telemetryTransport = telemetryTransport

		let diagnosticStream = AsyncStream.makeStream(
			of: DecartRealtimeDiagnosticEvent.self,
			bufferingPolicy: .bufferingNewest(100)
		)
		self.diagnosticUpdates = diagnosticStream.stream
		self.diagnosticContinuation = diagnosticStream.continuation

		let statsStream = AsyncStream.makeStream(
			of: DecartRealtimeWebRTCStats.self,
			bufferingPolicy: .bufferingNewest(10)
		)
		self.statsUpdates = statsStream.stream
		self.statsContinuation = statsStream.continuation

	}

	// Network-path instrumentation is started/stopped explicitly by the
	// manager around a session (mirroring the JS SDK, where it attaches on
	// room connect), and is intentionally decoupled from the forwarder so
	// the sink can be wired without immediately producing path events.
	func startNetworkMonitoring() {
		guard pathObserver == nil else { return }
		let observer = NetworkPathObserver { [weak self] snapshot, previous in
			Task { await self?.recordPathChange(snapshot: snapshot, previous: previous) }
		}
		pathObserver = observer
		observer.start()
	}

	func stopNetworkMonitoring() {
		pathObserver?.stop()
		pathObserver = nil
	}

	private func recordPathChange(snapshot: NetworkPathSnapshot, previous: NetworkPathSnapshot?) async {
		let data = Self.networkSnapshotData(snapshot)
		guard let previous else {
			await emitInstrumentationEvent("network-state", data: data)
			return
		}
		await emitInstrumentationEvent("network-change", data: data)
		let online = snapshot.status == "satisfied"
		let wasOnline = previous.status == "satisfied"
		if online, !wasOnline {
			await emitInstrumentationEvent("browser-online", data: data)
		} else if !online, wasOnline {
			await emitInstrumentationEvent("browser-offline", data: data)
		}
	}

	private static func networkSnapshotData(_ snapshot: NetworkPathSnapshot) -> [String: DecartRealtimeJSONValue] {
		// Per-interface local IP addresses (en0=Wi-Fi, pdp_ip0=cellular, …),
		// since `NWPath` only exposes interface *types*, not the actual
		// addresses that are useful for correlating with the gathered ICE
		// host candidates.
		let addresses = NetworkPathObserver.interfaceAddresses().mapValues { ips in
			DecartRealtimeJSONValue.array(ips.map { .string($0) })
		}
		return [
			"online": .bool(snapshot.status == "satisfied"),
			"status": .string(snapshot.status),
			"interfaces": .array(snapshot.interfaces.map { .string($0) }),
			"addresses": .object(addresses),
			"isExpensive": .bool(snapshot.isExpensive),
			"isConstrained": .bool(snapshot.isConstrained)
		]
	}

	func setObservabilityForwarder(_ forwarder: ObservabilityForwarder?) {
		observabilityForwarder = forwarder
		if forwarder != nil {
			lastSelectedPairSignature = nil
			lastIceState = nil
			lastCandidatePairStates.removeAll()
			connectionDiagnosticsEnabled = true
			DecartLiveKitLogging.setActiveObservability(self)
		} else {
			DecartLiveKitLogging.setActiveObservability(nil)
		}
	}

	func setConnectionDiagnosticsEnabled(_ enabled: Bool) {
		connectionDiagnosticsEnabled = enabled
		if enabled {
			lastSelectedPairSignature = nil
			lastIceState = nil
			lastCandidatePairStates.removeAll()
		}
	}

	/// Forwards a LiveKit-originated connection log over the observability WS.
	/// Used to surface ICE / transport / signaling detail during the connection
	/// handshake (including failures that happen before any track stats exist).
	func recordLiveKitConnectionLog(
		_ message: String,
		level: DecartRealtimeLogLevel,
		category: String,
		metadata: [String: String]
	) async {
		await emitInstrumentationEvent(
			"livekit-log",
			data: [
				"level": .string(level.rawValue),
				"category": .string(category),
				"message": .string(message),
				"metadata": .object(metadata.mapValues { .string($0) })
			]
		)
	}

	// Logs are local-only, matching the JS SDK: they go to the SDK logger,
	// never over the realtime WebSocket and never in the telemetry POST.
	// Connection issues surface over the WS as structured diagnostics
	// (`client-session-connection-breakdown`, `reconnect`) and instrumentation
	// events instead.
	nonisolated func emitLog(
		_ message: String,
		level: DecartRealtimeLogLevel = .debug,
		category: String,
		metadata: [String: String] = [:]
	) {
		Self.logLocally(message, level: level, category: category, metadata: metadata)
	}

	func recordLog(
		_ message: String,
		level: DecartRealtimeLogLevel = .debug,
		category: String,
		metadata: [String: String] = [:]
	) async {
		Self.logLocally(message, level: level, category: category, metadata: metadata)
	}

	private nonisolated static func logLocally(
		_ message: String,
		level: DecartRealtimeLogLevel,
		category: String,
		metadata: [String: String]
	) {
		let suffix = metadata.isEmpty
			? ""
			: " " + metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
		DecartLogger.log("[\(category)] \(message)\(suffix)", level: level.decartLoggerLevel)
	}

	func emitInstrumentationEvent(
		_ name: String,
		data: [String: DecartRealtimeJSONValue] = [:],
		timestamp: Int64 = DecartRealtimeClock.nowMilliseconds()
	) async {
		await forwardObservability([
			"kind": .string("instrumentation"),
			"name": .string(name),
			"data": .object(data),
			"timestamp": .int(Int(timestamp))
		])
	}

	private func forwardObservability(_ payload: [String: DecartRealtimeJSONValue]) async {
		guard let observabilityForwarder else { return }
		await observabilityForwarder(.object(payload))
	}

	func diagnostic(
		_ name: String,
		data: [String: DecartRealtimeJSONValue],
		timestamp: Int64 = DecartRealtimeClock.nowMilliseconds()
	) async {
		let event = DecartRealtimeDiagnosticEvent(name: name, data: data, timestamp: timestamp)
		diagnosticContinuation.yield(event)
		if telemetryEnabled {
			diagnosticsBuffer.append(event)
		}
		await forwardObservability([
			"kind": .string("diagnostic"),
			"name": .string(name),
			"data": .object(data),
			"timestamp": .int(Int(timestamp))
		])
	}

	func recordStats(_ stats: DecartRealtimeWebRTCStats) async {
		statsContinuation.yield(stats)
		if telemetryEnabled, sessionId != nil {
			statsBuffer.append(stats)
		}
		await detectVideoStall(stats)
		guard connectionDiagnosticsEnabled else { return }
		await detectIceConnectionStateChange(stats)
		await detectCandidatePairChanges(stats)
		await detectSelectedCandidatePairChange(stats)
	}

	// Emits the ICE transport state (checking/connected/failed/disconnected/…)
	// whenever it changes — the closest signal to "connection attempt
	// progress" reachable on iOS, where LiveKit does not expose the underlying
	// peer connection's ICE events.
	private func detectIceConnectionStateChange(_ stats: DecartRealtimeWebRTCStats) async {
		guard let iceState = stats.connection.iceState else { return }
		guard iceState != lastIceState else { return }
		let previous = lastIceState
		lastIceState = iceState

		var data: [String: DecartRealtimeJSONValue] = ["state": .string(iceState)]
		if let previous {
			data["previousState"] = .string(previous)
		}
		if let dtlsState = stats.connection.dtlsState {
			data["dtlsState"] = .string(dtlsState)
		}
		if let selectedCandidatePairId = stats.connection.selectedCandidatePairId {
			data["selectedCandidatePairId"] = .string(selectedCandidatePairId)
		}
		if let iceRole = stats.connection.iceRole {
			data["iceRole"] = .string(iceRole)
		}
		if let iceLocalUsernameFragment = stats.connection.iceLocalUsernameFragment {
			data["iceLocalUsernameFragment"] = .string(iceLocalUsernameFragment)
		}
		if let changes = stats.connection.selectedCandidatePairChanges {
			data["selectedCandidatePairChanges"] = .int(changes)
		}
		await emitInstrumentationEvent("ice-connection-state", data: data)
	}

	// Emits one `ice-candidate-pair` event per candidate pair whenever a pair
	// first appears or transitions state (e.g. waiting → in-progress → failed
	// or succeeded). This surfaces every connection attempt and any failing
	// ones, with the STUN connectivity-check counts.
	private func detectCandidatePairChanges(_ stats: DecartRealtimeWebRTCStats) async {
		for pair in stats.connection.candidatePairs {
			let signature = "\(pair.state)|\(pair.nominated)"
			if lastCandidatePairStates[pair.id] == signature { continue }
			lastCandidatePairStates[pair.id] = signature

			var data: [String: DecartRealtimeJSONValue] = [
				"id": .string(pair.id),
				"state": .string(pair.state),
				"nominated": .bool(pair.nominated)
			]
			if let transportId = pair.transportId {
				data["transportId"] = .string(transportId)
			}
			if let localCandidateId = pair.localCandidateId {
				data["localCandidateId"] = .string(localCandidateId)
			}
			if let remoteCandidateId = pair.remoteCandidateId {
				data["remoteCandidateId"] = .string(remoteCandidateId)
			}
			if let rtt = pair.currentRoundTripTimeMs {
				data["currentRoundTripTimeMs"] = .double(rtt)
			}
			if let requestsSent = pair.requestsSent {
				data["requestsSent"] = .int(requestsSent)
			}
			if let responsesReceived = pair.responsesReceived {
				data["responsesReceived"] = .int(responsesReceived)
			}
			if let requestsReceived = pair.requestsReceived {
				data["requestsReceived"] = .int(requestsReceived)
			}
			if let responsesSent = pair.responsesSent {
				data["responsesSent"] = .int(responsesSent)
			}
			if let consentRequestsSent = pair.consentRequestsSent {
				data["consentRequestsSent"] = .int(consentRequestsSent)
			}
			if let lastPacketSentTimestamp = pair.lastPacketSentTimestamp {
				data["lastPacketSentTimestamp"] = .double(lastPacketSentTimestamp)
			}
			if let lastPacketReceivedTimestamp = pair.lastPacketReceivedTimestamp {
				data["lastPacketReceivedTimestamp"] = .double(lastPacketReceivedTimestamp)
			}
			if let bytesSent = pair.bytesSent {
				data["bytesSent"] = .int(Int(bytesSent))
			}
			if let bytesReceived = pair.bytesReceived {
				data["bytesReceived"] = .int(Int(bytesReceived))
			}
			if let packetsDiscardedOnSend = pair.packetsDiscardedOnSend {
				data["packetsDiscardedOnSend"] = .int(packetsDiscardedOnSend)
			}
			if let bytesDiscardedOnSend = pair.bytesDiscardedOnSend {
				data["bytesDiscardedOnSend"] = .int(Int(bytesDiscardedOnSend))
			}
			await emitInstrumentationEvent("ice-candidate-pair", data: data)
		}
	}

	// Stats themselves are intentionally not forwarded over the WS (they fire
	// every second and would dominate the signal). But the selected ICE
	// candidate pair is the single most useful datum for diagnosing a
	// connection failure, so we surface it as a `selected-candidate-pair`
	// instrumentation event whenever the winning pair first appears or changes.
	private func detectSelectedCandidatePairChange(_ stats: DecartRealtimeWebRTCStats) async {
		guard let pair = stats.connection.selectedCandidatePairs.first else { return }
		let signature = "\(pair.local.candidateType)|\(pair.local.address):\(pair.local.port)|\(pair.remote.candidateType)|\(pair.remote.address):\(pair.remote.port)"
		guard signature != lastSelectedPairSignature else { return }
		lastSelectedPairSignature = signature

		var data: [String: DecartRealtimeJSONValue] = [
			"local": .object([
				"type": .string(pair.local.candidateType),
				"protocol": .string(pair.local.protocol),
				"address": .string(pair.local.address),
				"port": .int(pair.local.port)
			]),
			"remote": .object([
				"type": .string(pair.remote.candidateType),
				"protocol": .string(pair.remote.protocol),
				"address": .string(pair.remote.address),
				"port": .int(pair.remote.port)
			])
		]
		if let rtt = stats.connection.currentRoundTripTime {
			data["currentRoundTripTimeMs"] = .double(rtt * 1000)
		}
		if let availableOutgoingBitrate = stats.connection.availableOutgoingBitrate {
			data["availableOutgoingBitrate"] = .double(availableOutgoingBitrate)
		}
		await emitInstrumentationEvent("selected-candidate-pair", data: data)
	}

	private func detectVideoStall(_ stats: DecartRealtimeWebRTCStats) async {
		guard let video = stats.video else { return }
		if !videoStalled, video.framesPerSecond < 0.5 {
			videoStalled = true
			stallStartMs = stats.timestamp
			await diagnostic("videoStall", data: [
				"stalled": .bool(true),
				"durationMs": .int(0)
			], timestamp: stallStartMs)
		} else if videoStalled, video.framesPerSecond >= 0.5 {
			let duration = max(Int(stats.timestamp - stallStartMs), 0)
			videoStalled = false
			await diagnostic("videoStall", data: [
				"stalled": .bool(false),
				"durationMs": .int(duration)
			], timestamp: stats.timestamp)
		}
	}

	// MARK: - Connection breakdown diagnostics

	func beginConnectionBreakdown(attempt: Int, initialImageSizeKb: Int?) {
		connectionBreakdown = ConnectionBreakdownBuffer(
			attempt: attempt,
			connectStartedAt: DecartRealtimeClock.nowMilliseconds(),
			initialImageSizeKb: initialImageSizeKb
		)
		// Capture LiveKit's verbose connection logs for the duration of the
		// handshake so ICE/transport detail is recorded even if it fails.
		DecartLiveKitLogging.setCaptureVerbose(true)
	}

	func startPhase(_ name: String) {
		guard connectionBreakdown != nil else { return }
		if connectionBreakdown?.phases[name] == nil {
			connectionBreakdown?.phaseOrder.append(name)
		}
		connectionBreakdown?.phases[name] = ConnectionPhaseEntry(startedAt: DecartRealtimeClock.nowMilliseconds())
	}

	func endPhase(_ name: String, success: Bool, error: String? = nil) {
		guard var entry = connectionBreakdown?.phases[name] else { return }
		entry.endedAt = DecartRealtimeClock.nowMilliseconds()
		entry.success = success
		if let error {
			entry.error = error
		}
		connectionBreakdown?.phases[name] = entry
	}

	func recordLiveKitConnectSpan(_ snapshot: LiveKitConnectSpanSnapshot) {
		guard connectionBreakdown != nil else { return }
		connectionBreakdown?.liveKitConnectSpan = snapshot
	}

	func finishConnectionBreakdown(success: Bool, error: String? = nil) async {
		DecartLiveKitLogging.setCaptureVerbose(false)
		guard let buffer = connectionBreakdown else { return }
		connectionBreakdown = nil

		let now = DecartRealtimeClock.nowMilliseconds()
		var phases: [DecartRealtimeJSONValue] = []
		for name in buffer.phaseOrder {
			guard let entry = buffer.phases[name] else { continue }
			let unfinished = entry.endedAt == nil
			let endedAt = entry.endedAt ?? now
			let phaseSuccess = entry.success ?? false
			let phaseError = entry.error ?? ((unfinished && !success) ? error : nil)
			var object: [String: DecartRealtimeJSONValue] = [
				"phase": .string(name),
				"durationMs": .int(Int(endedAt - entry.startedAt)),
				"success": .bool(phaseSuccess)
			]
			if let phaseError {
				object["error"] = .string(phaseError)
			}
			phases.append(.object(object))
		}

		var data: [String: DecartRealtimeJSONValue] = [
			"attempt": .int(buffer.attempt),
			"success": .bool(success),
			"totalDurationMs": .int(Int(now - buffer.connectStartedAt)),
			"initialImageSizeKb": buffer.initialImageSizeKb.map { .int($0) } ?? .null,
			"phases": .array(phases)
		]
		if let liveKitConnectSpan = buffer.liveKitConnectSpan {
			data["liveKitConnectSpan"] = Self.liveKitConnectSpanData(liveKitConnectSpan)
		}
		if let error {
			data["error"] = .string(error)
		}
		await diagnostic("client-session-connection-breakdown", data: data, timestamp: now)
	}

	func recordReconnect(
		attempt: Int,
		maxAttempts: Int,
		durationMs: Int,
		success: Bool,
		error: String? = nil
	) async {
		var data: [String: DecartRealtimeJSONValue] = [
			"attempt": .int(attempt),
			"maxAttempts": .int(maxAttempts),
			"durationMs": .int(durationMs),
			"success": .bool(success)
		]
		if let error {
			data["error"] = .string(error)
		}
		await diagnostic("reconnect", data: data, timestamp: DecartRealtimeClock.nowMilliseconds())
	}

	func sessionStarted(_ sessionId: String) {
		guard telemetryEnabled else { return }
		self.sessionId = sessionId
		telemetryTask?.cancel()
		let reportIntervalNanoseconds = reportIntervalNanoseconds
		telemetryTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(nanoseconds: reportIntervalNanoseconds)
				await self?.flush()
			}
		}
	}

	func stopTelemetry() async {
		telemetryTask?.cancel()
		telemetryTask = nil
		sessionId = nil
		statsBuffer.removeAll()
		diagnosticsBuffer.removeAll()
		videoStalled = false
		stallStartMs = 0
		lastSelectedPairSignature = nil
		lastIceState = nil
		lastCandidatePairStates.removeAll()
		connectionDiagnosticsEnabled = true
		connectionBreakdown = nil
	}

	func finish() async {
		DecartLiveKitLogging.setActiveObservability(nil)
		DecartLiveKitLogging.setCaptureVerbose(false)
		pathObserver?.stop()
		pathObserver = nil
		await stopTelemetry()
		diagnosticContinuation.finish()
		statsContinuation.finish()
	}

	func flushPendingIfNeeded() async {
		guard telemetryEnabled else { return }
		let hasPending = !statsBuffer.isEmpty || !diagnosticsBuffer.isEmpty
		guard hasPending else { return }
		let effectiveSessionId = sessionId ?? "pre-session-\(UUID().uuidString)"
		await flushReports(sessionId: effectiveSessionId)
	}

	private static func liveKitConnectSpanData(_ snapshot: LiveKitConnectSpanSnapshot) -> DecartRealtimeJSONValue {
		.object([
			"totalDurationMs": .int(snapshot.totalDurationMs),
			"events": .array(snapshot.entries.map { entry in
				.object([
					"label": .string(entry.label),
					"elapsedMs": .int(entry.elapsedMs),
					"deltaMs": .int(entry.deltaMs)
				])
			})
		])
	}

	private func flush() async {
		guard telemetryEnabled, let sessionId else { return }
		await flushReports(sessionId: sessionId)
	}

	private func flushReports(sessionId: String) async {
		guard let apiKey, !apiKey.isEmpty else { return }
		while let report = makeReport(sessionId: sessionId) {
			var request = URLRequest(url: telemetryURL)
			request.httpMethod = "POST"
			request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
			request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.timeoutInterval = 5

			do {
				request.httpBody = try JSONEncoder().encode(report)
				_ = try await telemetryTransport(request)
			} catch {
				// Telemetry is best-effort and must not affect realtime sessions.
			}
		}
	}

	private func makeReport(sessionId: String) -> TelemetryReport? {
		guard !statsBuffer.isEmpty || !diagnosticsBuffer.isEmpty else {
			return nil
		}

		let stats = Array(statsBuffer.prefix(maxItemsPerReport))
		statsBuffer.removeFirst(stats.count)

		let diagnostics = Array(diagnosticsBuffer.prefix(maxItemsPerReport))
		diagnosticsBuffer.removeFirst(diagnostics.count)

		let tags = [
			"session_id": sessionId,
			"sdk_version": DecartUserAgent.sdkVersion,
			"model": model
		]

		return TelemetryReport(
			sessionId: sessionId,
			timestamp: DecartRealtimeClock.nowMilliseconds(),
			sdkVersion: DecartUserAgent.sdkVersion,
			model: model,
			tags: tags,
			stats: stats,
			diagnostics: diagnostics.map(TelemetryDiagnostic.init)
		)
	}

}

private struct ConnectionBreakdownBuffer {
	let attempt: Int
	let connectStartedAt: Int64
	let initialImageSizeKb: Int?
	var phaseOrder: [String] = []
	var phases: [String: ConnectionPhaseEntry] = [:]
	var liveKitConnectSpan: LiveKitConnectSpanSnapshot?
}

private struct ConnectionPhaseEntry {
	let startedAt: Int64
	var endedAt: Int64?
	var success: Bool?
	var error: String?
}

private extension DecartRealtimeLogLevel {
	var decartLoggerLevel: DecartLogger.Level {
		switch self {
		case .debug, .info: return .info
		case .warning: return .warning
		case .error: return .error
		}
	}
}

private struct TelemetryReport: Encodable {
	let sessionId: String
	let timestamp: Int64
	let sdkVersion: String
	let model: String
	let tags: [String: String]
	let stats: [DecartRealtimeWebRTCStats]
	let diagnostics: [TelemetryDiagnostic]
}

private struct TelemetryDiagnostic: Encodable {
	let name: String
	let data: [String: DecartRealtimeJSONValue]
	let timestamp: Int64

	init(_ event: DecartRealtimeDiagnosticEvent) {
		self.name = event.name
		self.data = event.data
		self.timestamp = event.timestamp
	}
}
