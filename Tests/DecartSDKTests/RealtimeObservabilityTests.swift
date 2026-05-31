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

	func payloadCount() -> Int {
		payloads.count
	}
}
