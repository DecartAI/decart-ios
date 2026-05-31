import Foundation
import XCTest
@testable import DecartSDK

final class RealtimeObservabilityTests: XCTestCase {
	func testStatsUseHTTPOnly() async throws {
		let telemetry = TelemetryRequestRecorder()
		let websocket = ObservabilityPayloadRecorder()
		let observability = makeObservability(telemetry: telemetry)

		await observability.setObservabilityForwarder { payload in
			await websocket.record(payload)
		}
		await observability.sessionStarted("session-123")
		await observability.recordStats(Self.makeStats())
		await observability.flushPendingIfNeeded()

		let requestCount = await telemetry.requestCount()
		let payloadCount = await websocket.payloadCount()
		XCTAssertEqual(requestCount, 1)
		XCTAssertEqual(payloadCount, 0)
	}

	func testDiagnosticUsesHTTPAndWebSocketObservability() async throws {
		let telemetry = TelemetryRequestRecorder()
		let websocket = ObservabilityPayloadRecorder()
		let observability = makeObservability(telemetry: telemetry)

		await observability.setObservabilityForwarder { payload in
			await websocket.record(payload)
		}
		await observability.sessionStarted("session-123")
		await observability.diagnostic("phaseTiming", data: ["phase": .string("websocket-open")], timestamp: 123)
		await observability.flushPendingIfNeeded()

		let requestCount = await telemetry.requestCount()
		let firstPayload = await websocket.firstPayloadObject()
		XCTAssertEqual(requestCount, 1)
		let payload = try XCTUnwrap(firstPayload)
		XCTAssertEqual(payload["kind"], .string("diagnostic"))
		XCTAssertEqual(payload["name"], .string("phaseTiming"))
		XCTAssertEqual(payload["timestamp"], .int(123))
	}

	func testInstrumentationUsesWebSocketOnly() async throws {
		let telemetry = TelemetryRequestRecorder()
		let websocket = ObservabilityPayloadRecorder()
		let observability = makeObservability(telemetry: telemetry)

		await observability.setObservabilityForwarder { payload in
			await websocket.record(payload)
		}
		await observability.sessionStarted("session-123")
		await observability.emitInstrumentationEvent("room-connected", data: ["roomName": .string("room-123")], timestamp: 456)
		await observability.flushPendingIfNeeded()

		let requestCount = await telemetry.requestCount()
		let firstPayload = await websocket.firstPayloadObject()
		XCTAssertEqual(requestCount, 0)
		let payload = try XCTUnwrap(firstPayload)
		XCTAssertEqual(payload["kind"], .string("instrumentation"))
		XCTAssertEqual(payload["name"], .string("room-connected"))
		XCTAssertEqual(payload["timestamp"], .int(456))
	}

	func testTelemetryOptOutStillAllowsWebSocketObservability() async throws {
		let telemetry = TelemetryRequestRecorder()
		let websocket = ObservabilityPayloadRecorder()
		let observability = RealtimeObservability(
			apiKey: "client-api-key",
			model: "test-model",
			telemetryEnabled: false,
			telemetryTransport: { request in
				await telemetry.record(request)
			}
		)

		await observability.setObservabilityForwarder { payload in
			await websocket.record(payload)
		}
		await observability.diagnostic("phaseTiming", data: ["phase": .string("websocket-open")], timestamp: 789)
		await observability.flushPendingIfNeeded()

		let requestCount = await telemetry.requestCount()
		let firstPayload = await websocket.firstPayloadObject()
		XCTAssertEqual(requestCount, 0)
		let payload = try XCTUnwrap(firstPayload)
		XCTAssertEqual(payload["kind"], .string("diagnostic"))
	}

	func testTelemetryWithoutAPIKeyDoesNotSendHTTP() async {
		let recorder = TelemetryRequestRecorder()
		let observability = RealtimeObservability(
			apiKey: nil,
			model: "test-model",
			telemetryEnabled: true,
			telemetryTransport: { request in
				await recorder.record(request)
			}
		)

		await observability.sessionStarted("session-123")
		await observability.recordStats(Self.makeStats())
		await observability.flushPendingIfNeeded()

		let requestCount = await recorder.requestCount()
		XCTAssertEqual(requestCount, 0)
	}

	func testTelemetryUsesProvidedClientAPIKey() async throws {
		let recorder = TelemetryRequestRecorder()
		let observability = makeObservability(telemetry: recorder)

		await observability.sessionStarted("session-123")
		await observability.recordStats(Self.makeStats())
		await observability.flushPendingIfNeeded()

		let recordedRequest = await recorder.firstRequest()
		let request = try XCTUnwrap(recordedRequest)
		XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-KEY"), "client-api-key")
		XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), DecartUserAgent.build())
		XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
	}

	func testConnectionBreakdownDiagnosticForwardedOverWebSocket() async throws {
		let telemetry = TelemetryRequestRecorder()
		let websocket = ObservabilityPayloadRecorder()
		let observability = makeObservability(telemetry: telemetry)

		await observability.setObservabilityForwarder { payload in
			await websocket.record(payload)
		}
		await observability.beginConnectionBreakdown(attempt: 2, initialImageSizeKb: 17)
		await observability.startPhase("websocket-open")
		await observability.endPhase("websocket-open", success: true)
		await observability.startPhase("room-join")
		await observability.endPhase("room-join", success: false, error: "boom")
		await observability.finishConnectionBreakdown(success: false, error: "boom")

		let firstPayload = await websocket.firstPayloadObject()
		let payload = try XCTUnwrap(firstPayload)
		XCTAssertEqual(payload["kind"], .string("diagnostic"))
		XCTAssertEqual(payload["name"], .string("client-session-connection-breakdown"))
		guard case .object(let data)? = payload["data"] else {
			return XCTFail("missing data object")
		}
		XCTAssertEqual(data["attempt"], .int(2))
		XCTAssertEqual(data["success"], .bool(false))
		XCTAssertEqual(data["initialImageSizeKb"], .int(17))
		XCTAssertEqual(data["error"], .string("boom"))
		guard case .array(let phases)? = data["phases"] else {
			return XCTFail("missing phases array")
		}
		XCTAssertEqual(phases.count, 2)
		guard case .object(let firstPhase) = phases[0], case .object(let secondPhase) = phases[1] else {
			return XCTFail("malformed phases")
		}
		XCTAssertEqual(firstPhase["phase"], .string("websocket-open"))
		XCTAssertEqual(firstPhase["success"], .bool(true))
		XCTAssertEqual(secondPhase["phase"], .string("room-join"))
		XCTAssertEqual(secondPhase["success"], .bool(false))
		XCTAssertEqual(secondPhase["error"], .string("boom"))
	}

	func testReconnectDiagnosticForwardedOverWebSocket() async throws {
		let telemetry = TelemetryRequestRecorder()
		let websocket = ObservabilityPayloadRecorder()
		let observability = makeObservability(telemetry: telemetry)

		await observability.setObservabilityForwarder { payload in
			await websocket.record(payload)
		}
		await observability.recordReconnect(attempt: 3, maxAttempts: 5, durationMs: 1200, success: true)

		let firstPayload = await websocket.firstPayloadObject()
		let payload = try XCTUnwrap(firstPayload)
		XCTAssertEqual(payload["kind"], .string("diagnostic"))
		XCTAssertEqual(payload["name"], .string("reconnect"))
		guard case .object(let data)? = payload["data"] else {
			return XCTFail("missing data object")
		}
		XCTAssertEqual(data["attempt"], .int(3))
		XCTAssertEqual(data["maxAttempts"], .int(5))
		XCTAssertEqual(data["durationMs"], .int(1200))
		XCTAssertEqual(data["success"], .bool(true))
	}

	func testSelectedCandidatePairForwardedFromStatsAndDeduped() async throws {
		let telemetry = TelemetryRequestRecorder()
		let websocket = ObservabilityPayloadRecorder()
		let observability = makeObservability(telemetry: telemetry)

		await observability.setObservabilityForwarder { payload in
			await websocket.record(payload)
		}
		await observability.recordStats(Self.makeStatsWithSelectedPair())
		await observability.recordStats(Self.makeStatsWithSelectedPair())

		let payloadCount = await websocket.payloadCount()
		XCTAssertEqual(payloadCount, 1, "identical selected pair should only emit once")
		let firstPayload = await websocket.firstPayloadObject()
		let payload = try XCTUnwrap(firstPayload)
		XCTAssertEqual(payload["kind"], .string("instrumentation"))
		XCTAssertEqual(payload["name"], .string("selected-candidate-pair"))
		guard case .object(let data)? = payload["data"], case .object(let local)? = data["local"] else {
			return XCTFail("missing selected pair payload")
		}
		XCTAssertEqual(local["type"], .string("host"))
		XCTAssertEqual(local["address"], .string("10.0.0.1"))
		XCTAssertEqual(data["currentRoundTripTimeMs"], .double(40))
	}

	func testIceConnectionStateAndCandidatePairsForwarded() async throws {
		let telemetry = TelemetryRequestRecorder()
		let websocket = ObservabilityPayloadRecorder()
		let observability = makeObservability(telemetry: telemetry)

		await observability.setObservabilityForwarder { payload in
			await websocket.record(payload)
		}
		await observability.recordStats(Self.makeStatsWithIce())
		// Identical second snapshot must not re-emit unchanged ICE state/pairs.
		await observability.recordStats(Self.makeStatsWithIce())

		let objects = await websocket.objects()
		let names = objects.compactMap { object -> String? in
			if case .string(let name)? = object["name"] { return name }
			return nil
		}
		XCTAssertEqual(names.filter { $0 == "ice-connection-state" }.count, 1)
		XCTAssertEqual(names.filter { $0 == "ice-candidate-pair" }.count, 2)

		let iceStateObject = objects.first { $0["name"] == .string("ice-connection-state") }
		let iceState = try XCTUnwrap(iceStateObject)
		guard case .object(let iceData)? = iceState["data"] else {
			return XCTFail("missing ice-connection-state data")
		}
		XCTAssertEqual(iceData["state"], .string("checking"))
		XCTAssertEqual(iceData["dtlsState"], .string("connecting"))

		let failedPair = objects.first {
			guard case .object(let data)? = $0["data"] else { return false }
			return data["id"] == .string("pair-failed")
		}
		let failed = try XCTUnwrap(failedPair)
		guard case .object(let failedData)? = failed["data"] else {
			return XCTFail("missing failed pair data")
		}
		XCTAssertEqual(failedData["state"], .string("failed"))
		XCTAssertEqual(failedData["requestsSent"], .int(5))
		XCTAssertEqual(failedData["responsesReceived"], .int(0))
	}

	func testLiveKitConnectionLogForwardedOverWebSocketOnly() async throws {
		let telemetry = TelemetryRequestRecorder()
		let websocket = ObservabilityPayloadRecorder()
		let observability = makeObservability(telemetry: telemetry)

		await observability.setObservabilityForwarder { payload in
			await websocket.record(payload)
		}
		await observability.recordLiveKitConnectionLog(
			"target: subscriber, connectionState: failed",
			level: .warning,
			category: "livekit.Room",
			metadata: ["target": "subscriber"]
		)

		let requestCount = await telemetry.requestCount()
		let firstPayload = await websocket.firstPayloadObject()
		XCTAssertEqual(requestCount, 0, "livekit-log is WS-only, never POSTed")
		let payload = try XCTUnwrap(firstPayload)
		XCTAssertEqual(payload["kind"], .string("instrumentation"))
		XCTAssertEqual(payload["name"], .string("livekit-log"))
		guard case .object(let data)? = payload["data"] else {
			return XCTFail("missing livekit-log data")
		}
		XCTAssertEqual(data["level"], .string("warning"))
		XCTAssertEqual(data["category"], .string("livekit.Room"))
		XCTAssertEqual(data["message"], .string("target: subscriber, connectionState: failed"))
	}

	func testLiveKitLogAllowlistKeepsConnectionDiagnostics() {
		// Dropped by default: routine chatter the server already logs, plus
		// per-candidate trickle sends, SDP/data-channel/negotiation, and empty.
		let droppedSamples = [
			"",
			"   ",
			"sending iceCandidate",
			"ServerInfo(version: 1.2.3, region: us-east)",
			"Join response id ABC waiting",
			"ping/pong starting interval: 5",
			"enabledPublishCodecs: [h264, vp8]",
			"Configuring transports with JOIN response...",
			"subscriberPrimary: false singlePeerConnection: true",
			"did update subscriptionPermission allParticipantsAllowed: true",
			"AsyncCompleter<JoinResponse> waiting for join response",
			"Primary transport connect id XYZ waiting",
			"type: LKRTCAudioTrack name: mic streams: [stream0]",
			"dataChannel.Optional(\"_reliable\") : Optional(-1)",
			"ShouldNegotiate for publisher",
			"sending offer",
			"setting local description",
			"[Connect] Fast publish enabled: true"
		]
		for line in droppedSamples {
			XCTAssertFalse(LiveKitLogNoiseFilter.isDiagnostic(line), "should drop: \(line)")
		}

		// Forwarded: connection/ICE state transitions and failures.
		let keptSamples = [
			"Transport(subscriber) did update state: failed",
			"Transport(publisher) did update state: connected",
			"target: subscriber, connectionState: disconnected",
			"Failed to add ice candidate for target: subscriber",
			"Failed to send iceCandidate, error: timeout",
			"Connect failed with region: us-east",
			"Primary transport connect timed out",
			"Unable to connect to signaling server",
			"Performing ICE restart"
		]
		for line in keptSamples {
			XCTAssertTrue(LiveKitLogNoiseFilter.isDiagnostic(line), "should keep: \(line)")
		}
	}

	func testLogsAreNotForwardedOverWebSocket() async throws {
		let telemetry = TelemetryRequestRecorder()
		let websocket = ObservabilityPayloadRecorder()
		let observability = makeObservability(telemetry: telemetry)

		await observability.setObservabilityForwarder { payload in
			await websocket.record(payload)
		}
		await observability.recordLog("connection failed", level: .error, category: "realtime.connection")
		observability.emitLog("livekit warning", level: .warning, category: "livekit.room")

		let payloadCount = await websocket.payloadCount()
		let requestCount = await telemetry.requestCount()
		XCTAssertEqual(payloadCount, 0, "logs must never go over the observability WS")
		XCTAssertEqual(requestCount, 0, "logs must never be POSTed as telemetry")
	}

	private static func makeStatsWithIce() -> DecartRealtimeWebRTCStats {
		DecartRealtimeWebRTCStats(
			timestamp: 3_000,
			video: nil,
			outboundVideo: nil,
			remoteInbound: nil,
			connection: .init(
				currentRoundTripTime: 0.05,
				availableOutgoingBitrate: 500_000,
				selectedCandidatePairs: [],
				candidatePairStates: ["failed": 1, "in-progress": 1],
				iceState: "checking",
				dtlsState: "connecting",
				selectedCandidatePairChanges: 0,
				candidatePairs: [
					.init(id: "pair-failed", state: "failed", nominated: false, requestsSent: 5, responsesReceived: 0),
					.init(
						id: "pair-active",
						state: "in-progress",
						nominated: true,
						currentRoundTripTimeMs: 50,
						requestsSent: 3,
						responsesReceived: 2
					)
				]
			)
		)
	}

	private static func makeStatsWithSelectedPair() -> DecartRealtimeWebRTCStats {
		DecartRealtimeWebRTCStats(
			timestamp: 2_000,
			video: nil,
			outboundVideo: nil,
			remoteInbound: nil,
			connection: .init(
				currentRoundTripTime: 0.04,
				availableOutgoingBitrate: 800_000,
				selectedCandidatePairs: [
					.init(
						local: .init(candidateType: "host", address: "10.0.0.1", port: 5000, protocol: "udp"),
						remote: .init(candidateType: "srflx", address: "203.0.113.7", port: 7000, protocol: "udp")
					)
				],
				candidatePairStates: ["succeeded": 1]
			)
		)
	}

	private func makeObservability(telemetry: TelemetryRequestRecorder) -> RealtimeObservability {
		RealtimeObservability(
			apiKey: "client-api-key",
			model: "test-model",
			telemetryEnabled: true,
			telemetryTransport: { request in
				await telemetry.record(request)
			}
		)
	}

	private static func makeStats() -> DecartRealtimeWebRTCStats {
		DecartRealtimeWebRTCStats(
			timestamp: 1_000,
			video: nil,
			outboundVideo: nil,
			remoteInbound: nil,
			connection: .init(
				currentRoundTripTime: nil,
				availableOutgoingBitrate: nil,
				selectedCandidatePairs: [],
				candidatePairStates: [:]
			)
		)
	}
}

private actor TelemetryRequestRecorder {
	private var requests: [URLRequest] = []

	func record(_ request: URLRequest) -> (Data, URLResponse) {
		requests.append(request)
		let response = HTTPURLResponse(
			url: request.url!,
			statusCode: 204,
			httpVersion: nil,
			headerFields: nil
		)!
		return (Data(), response)
	}

	func firstRequest() -> URLRequest? {
		requests.first
	}

	func requestCount() -> Int {
		requests.count
	}
}

private actor ObservabilityPayloadRecorder {
	private var payloads: [DecartRealtimeJSONValue] = []

	func record(_ payload: DecartRealtimeJSONValue) {
		payloads.append(payload)
	}

	func firstPayloadObject() -> [String: DecartRealtimeJSONValue]? {
		guard case .object(let object) = payloads.first else { return nil }
		return object
	}

	func objects() -> [[String: DecartRealtimeJSONValue]] {
		payloads.compactMap { payload in
			if case .object(let object) = payload { return object }
			return nil
		}
	}

	func payloadCount() -> Int {
		payloads.count
	}
}
