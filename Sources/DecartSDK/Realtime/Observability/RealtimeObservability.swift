import Foundation

actor RealtimeObservability {
	nonisolated let diagnosticUpdates: AsyncStream<DecartRealtimeDiagnosticEvent>
	nonisolated let statsUpdates: AsyncStream<DecartRealtimeWebRTCStats>
	nonisolated let logUpdates: AsyncStream<DecartRealtimeLogEvent>

	private let diagnosticContinuation: AsyncStream<DecartRealtimeDiagnosticEvent>.Continuation
	private let statsContinuation: AsyncStream<DecartRealtimeWebRTCStats>.Continuation
	private nonisolated let logContinuation: AsyncStream<DecartRealtimeLogEvent>.Continuation
	private var videoStalled = false
	private var stallStartMs: Int64 = 0

	init() {
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

		let logStream = AsyncStream.makeStream(
			of: DecartRealtimeLogEvent.self,
			bufferingPolicy: .bufferingNewest(200)
		)
		self.logUpdates = logStream.stream
		self.logContinuation = logStream.continuation
	}

	nonisolated func emitLog(
		_ message: String,
		level: DecartRealtimeLogLevel = .debug,
		category: String,
		metadata: [String: String] = [:]
	) {
		let event = DecartRealtimeLogEvent(
			level: level,
			category: category,
			message: message,
			metadata: metadata
		)
		logContinuation.yield(event)
	}

	func diagnostic(
		_ name: String,
		data: [String: DecartRealtimeJSONValue],
		timestamp: Int64 = DecartRealtimeClock.nowMilliseconds()
	) {
		let event = DecartRealtimeDiagnosticEvent(name: name, data: data, timestamp: timestamp)
		diagnosticContinuation.yield(event)
	}

	func recordStats(_ stats: DecartRealtimeWebRTCStats) {
		statsContinuation.yield(stats)
		detectVideoStall(stats)
		emitIceDiagnostic(from: stats)
	}

	func reset() {
		videoStalled = false
		stallStartMs = 0
	}

	func finish() async {
		reset()
		diagnosticContinuation.finish()
		statsContinuation.finish()
		logContinuation.finish()
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

	private func emitIceDiagnostic(from stats: DecartRealtimeWebRTCStats) {
		guard let pair = stats.connection.selectedCandidatePairs.first else { return }
		diagnostic("iceCandidatePair", data: [
			"localCandidateType": .string(pair.local.candidateType),
			"localProtocol": .string(pair.local.protocol),
			"remoteCandidateType": .string(pair.remote.candidateType),
			"remoteProtocol": .string(pair.remote.protocol),
			"currentRoundTripTime": stats.connection.currentRoundTripTime.map(DecartRealtimeJSONValue.double) ?? .null,
			"availableOutgoingBitrate": stats.connection.availableOutgoingBitrate.map(DecartRealtimeJSONValue.double) ?? .null
		], timestamp: stats.timestamp)
	}
}
