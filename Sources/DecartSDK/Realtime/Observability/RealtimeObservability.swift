import Foundation

actor RealtimeObservability {
	typealias TelemetryTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

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
	private var logsBuffer: [DecartRealtimeLogEvent] = []
	private var videoStalled = false
	private var stallStartMs: Int64 = 0
	private var pathObserver: NetworkPathObserver?

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

		if self.telemetryEnabled {
			Task { [weak self] in await self?.startPathMonitoring() }
		}
	}

	private func startPathMonitoring() {
		guard pathObserver == nil else { return }
		let observer = NetworkPathObserver { [weak self] snapshot, previous in
			Task { await self?.recordPathChange(snapshot: snapshot, previous: previous) }
		}
		pathObserver = observer
		observer.start()
	}

	private func recordPathChange(snapshot: NetworkPathSnapshot, previous: NetworkPathSnapshot?) {
		guard snapshot.status == "unsatisfied" else { return }
		recordLog(
			"network path became unsatisfied",
			level: .error,
			category: "network.path",
			metadata: [
				"interfaces": snapshot.interfaces.joined(separator: ","),
				"previousStatus": previous?.status ?? "none",
				"previousInterfaces": previous?.interfaces.joined(separator: ",") ?? "none",
				"isExpensive": "\(snapshot.isExpensive)",
				"isConstrained": "\(snapshot.isConstrained)"
			]
		)
	}

	nonisolated func emitLog(
		_ message: String,
		level: DecartRealtimeLogLevel = .debug,
		category: String,
		metadata: [String: String] = [:]
	) {
		guard telemetryEnabled else { return }
		let event = DecartRealtimeLogEvent(
			level: level,
			category: category,
			message: message,
			metadata: metadata
		)
		Task { [weak self] in await self?.appendLog(event) }
	}

	func recordLog(
		_ message: String,
		level: DecartRealtimeLogLevel = .debug,
		category: String,
		metadata: [String: String] = [:]
	) {
		guard telemetryEnabled else { return }
		appendLog(DecartRealtimeLogEvent(
			level: level,
			category: category,
			message: message,
			metadata: metadata
		))
	}

	private func appendLog(_ event: DecartRealtimeLogEvent) {
		let backpressureLimit = maxItemsPerReport * 4
		if logsBuffer.count >= backpressureLimit {
			logsBuffer.removeFirst(logsBuffer.count - backpressureLimit + 1)
		}
		logsBuffer.append(event)
	}

	func diagnostic(
		_ name: String,
		data: [String: DecartRealtimeJSONValue],
		timestamp: Int64 = DecartRealtimeClock.nowMilliseconds()
	) {
		let event = DecartRealtimeDiagnosticEvent(name: name, data: data, timestamp: timestamp)
		diagnosticContinuation.yield(event)
		if telemetryEnabled {
			diagnosticsBuffer.append(event)
		}
	}

	func recordStats(_ stats: DecartRealtimeWebRTCStats) {
		statsContinuation.yield(stats)
		if telemetryEnabled, sessionId != nil {
			statsBuffer.append(stats)
		}
		detectVideoStall(stats)
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
		logsBuffer.removeAll()
		videoStalled = false
		stallStartMs = 0
	}

	func finish() async {
		pathObserver?.stop()
		pathObserver = nil
		await stopTelemetry()
		diagnosticContinuation.finish()
		statsContinuation.finish()
	}

	func flushPendingIfNeeded() async {
		guard telemetryEnabled else { return }
		let hasPending = !statsBuffer.isEmpty || !diagnosticsBuffer.isEmpty || !logsBuffer.isEmpty
		guard hasPending else { return }
		let effectiveSessionId = sessionId ?? "pre-session-\(UUID().uuidString)"
		await flushReports(sessionId: effectiveSessionId)
	}

	private func flush() async {
		guard telemetryEnabled, let sessionId else { return }
		await flushReports(sessionId: sessionId)
	}

	private func flushReports(sessionId: String) async {
		guard let apiKey, !apiKey.isEmpty else { return }
		while let report = makeReport(sessionId: sessionId) {
			let containsLogs = !report.logs.isEmpty
			var request = URLRequest(url: telemetryURL)
			request.httpMethod = "POST"
			request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
			request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.timeoutInterval = 5

			do {
				request.httpBody = try JSONEncoder().encode(report)
				if containsLogs {
					print("[Decart telemetry] INFO sending logs to platform.decart.ai session=\(sessionId) logs=\(report.logs.count) stats=\(report.stats.count) diagnostics=\(report.diagnostics.count)")
					print("[Decart telemetry] DEBUG payload: \(debugRequestBody(request.httpBody))")
				}

				do {
					let (data, response) = try await telemetryTransport(request)
					if containsLogs {
						printTelemetryLogResult(response: response, data: data, logCount: report.logs.count)
					}
				} catch {
					if containsLogs {
						print("[Decart telemetry] ERROR logs POST request failed: \(error)")
					}
				}
			} catch {
				if containsLogs {
					print("[Decart telemetry] ERROR logs payload encode failed: \(error)")
				}
			}
		}
	}

	private func printTelemetryLogResult(response: URLResponse, data: Data, logCount: Int) {
		guard let httpResponse = response as? HTTPURLResponse else {
			print("[Decart telemetry] INFO logs POST completed logs=\(logCount) responseType=\(String(describing: type(of: response)))")
			return
		}

		if (200...299).contains(httpResponse.statusCode) {
			print("[Decart telemetry] INFO logs POST completed status=\(httpResponse.statusCode) logs=\(logCount)")
		} else {
			print("[Decart telemetry] ERROR logs POST failed status=\(httpResponse.statusCode) logs=\(logCount) body=\(debugResponseBody(data))")
		}
	}

	private func debugResponseBody(_ data: Data) -> String {
		guard !data.isEmpty else { return "<empty>" }
		let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>"
		let limit = 1_000
		guard body.count > limit else { return body }
		return "\(body.prefix(limit))...<truncated>"
	}

	private func debugRequestBody(_ data: Data?) -> String {
		guard let data, !data.isEmpty else { return "<empty>" }
		if let object = try? JSONSerialization.jsonObject(with: data),
		   let prettyData = try? JSONSerialization.data(
		   	withJSONObject: object,
		   	options: [.prettyPrinted, .sortedKeys]
		   ),
		   let prettyBody = String(data: prettyData, encoding: .utf8) {
			return prettyBody
		}
		return String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>"
	}

	private func makeReport(sessionId: String) -> TelemetryReport? {
		let logsChunk = drainLogs(limit: maxItemsPerReport)
		guard !statsBuffer.isEmpty || !diagnosticsBuffer.isEmpty || !logsChunk.isEmpty else {
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
			diagnostics: diagnostics.map(TelemetryDiagnostic.init),
			logs: logsChunk.map(TelemetryLog.init)
		)
	}

	private func drainLogs(limit: Int) -> [DecartRealtimeLogEvent] {
		let count = min(limit, logsBuffer.count)
		guard count > 0 else { return [] }
		let chunk = Array(logsBuffer.prefix(count))
		logsBuffer.removeFirst(count)
		return chunk
	}

	private func detectVideoStall(_ stats: DecartRealtimeWebRTCStats) {
		guard let video = stats.video else { return }
		if !videoStalled, video.framesPerSecond < 0.5 {
			videoStalled = true
			stallStartMs = stats.timestamp
			diagnostic("videoStall", data: [
				"stalled": .bool(true),
				"durationMs": .int(0)
			], timestamp: stallStartMs)
		} else if videoStalled, video.framesPerSecond >= 0.5 {
			let duration = max(Int(stats.timestamp - stallStartMs), 0)
			videoStalled = false
			diagnostic("videoStall", data: [
				"stalled": .bool(false),
				"durationMs": .int(duration)
			], timestamp: stats.timestamp)
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
	let logs: [TelemetryLog]
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

private struct TelemetryLog: Encodable {
	let timestamp: Int64
	let status: DecartRealtimeLogLevel
	let message: String
	let data: [String: String]?
	let tags: [String: String]

	init(_ event: DecartRealtimeLogEvent) {
		self.timestamp = event.timestamp
		self.status = event.level
		self.message = event.message
		self.data = event.metadata.isEmpty ? nil : event.metadata
		self.tags = ["category": event.category]
	}
}
