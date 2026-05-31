import Foundation
import XCTest
@testable import DecartSDK

final class RealtimeObservabilityTests: XCTestCase {
	func testTelemetryUsesProvidedClientAPIKey() async throws {
		let recorder = TelemetryRequestRecorder()
		let observability = RealtimeObservability(
			apiKey: "client-api-key",
			model: "test-model",
			telemetryEnabled: true,
			telemetryTransport: { request in
				await recorder.record(request)
			}
		)

		await observability.recordLog("connection successful", level: .info, category: "realtime.connection")
		await observability.flushPendingIfNeeded()

		let recordedRequest = await recorder.firstRequest()
		let request = try XCTUnwrap(recordedRequest)
		XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-KEY"), "client-api-key")
		XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), DecartUserAgent.build())
		XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
	}

	func testTelemetryWithoutAPIKeyDoesNotSend() async {
		let recorder = TelemetryRequestRecorder()
		let observability = RealtimeObservability(
			apiKey: nil,
			model: "test-model",
			telemetryEnabled: true,
			telemetryTransport: { request in
				await recorder.record(request)
			}
		)

		await observability.recordLog("connection successful", level: .info, category: "realtime.connection")
		await observability.flushPendingIfNeeded()

		let requestCount = await recorder.requestCount()
		XCTAssertEqual(requestCount, 0)
	}

	func testTelemetryOptOutDoesNotSend() async {
		let recorder = TelemetryRequestRecorder()
		let observability = RealtimeObservability(
			apiKey: "client-api-key",
			model: "test-model",
			telemetryEnabled: false,
			telemetryTransport: { request in
				await recorder.record(request)
			}
		)

		await observability.recordLog("connection successful", level: .info, category: "realtime.connection")
		await observability.flushPendingIfNeeded()

		let requestCount = await recorder.requestCount()
		XCTAssertEqual(requestCount, 0)
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
