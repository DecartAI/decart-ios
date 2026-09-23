import XCTest
@testable import DecartSDK

/// Pins the realtime signaling URL shape, in particular the optional
/// `speed=fast` query parameter (fast mode) next to the existing `resolution`.
final class SignalingURLTests: XCTestCase {
	private let configuration = DecartConfiguration(apiKey: "test-key")

	private func urlString(for options: RealtimeConfiguration) -> String {
		DecartClient.buildSignalingURLString(configuration: configuration, options: options)
	}

	private func occurrences(of needle: String, in haystack: String) -> Int {
		haystack.components(separatedBy: needle).count - 1
	}

	// MARK: - No option (default path must be byte-identical to before)

	func testNoSpeedOptionProducesUnchangedURL() {
		let url = urlString(for: RealtimeConfiguration(model: Models.realtime(.lucy2_5)))
		XCTAssertEqual(url, "wss://api.decart.ai/v1/stream?api_key=test-key&model=lucy-2.5")
		XCTAssertFalse(url.contains("speed"))
	}

	func testNoSpeedOptionWithResolutionAndDebugQualityProducesUnchangedURL() {
		let url = urlString(for: RealtimeConfiguration(
			model: Models.realtime(.lucy2_5),
			resolution: .p1080,
			debugQuality: true
		))
		XCTAssertEqual(url, "wss://api.decart.ai/v1/stream?api_key=test-key&model=lucy-2.5&resolution=1080p&pixel_latency=1")
		XCTAssertFalse(url.contains("speed"))
	}

	// MARK: - speed: .fast

	func testFastSpeedAppendsParamExactlyOnce() {
		let url = urlString(for: RealtimeConfiguration(model: Models.realtime(.lucy2_5), speed: .fast))
		XCTAssertEqual(url, "wss://api.decart.ai/v1/stream?api_key=test-key&model=lucy-2.5&speed=fast")
		XCTAssertEqual(occurrences(of: "speed=", in: url), 1)
		XCTAssertTrue(url.contains("&speed=fast"))
	}

	func testFastSpeedIsPlacedAfterResolutionAndBeforePixelLatency() {
		let url = urlString(for: RealtimeConfiguration(
			model: Models.realtime(.lucyVton3_5),
			resolution: .p1080,
			speed: .fast,
			debugQuality: true
		))
		XCTAssertEqual(
			url,
			"wss://api.decart.ai/v1/stream?api_key=test-key&model=lucy-vton-3.5&resolution=1080p&speed=fast&pixel_latency=1"
		)
		XCTAssertEqual(occurrences(of: "speed=", in: url), 1)
	}

	func testFastSpeedIsStillSentForModelWithoutTheCapability() {
		// The server ignores `speed` for models without the tier; the SDK warns
		// (see DecartClient.buildSignalingURLString) but must not throw or drop it.
		XCTAssertFalse(Models.realtime(.lucy2_1).supportedSpeeds.contains(.fast))
		let url = urlString(for: RealtimeConfiguration(model: Models.realtime(.lucy2_1), speed: .fast))
		XCTAssertEqual(url, "wss://api.decart.ai/v1/stream?api_key=test-key&model=lucy-2.1&speed=fast")
	}

	// MARK: - Reconnect path

	func testManagerStoresSignalingURLWithSpeedForReconnect() throws {
		// `DecartRealtimeManager` keeps the URL built at creation time in an
		// immutable property and dials it verbatim from both the initial
		// `performConnect` and every `scheduleReconnectIfNeeded` attempt (there is
		// no second URL builder), so the stored URL is what every re-dial uses.
		let client = DecartClient(decartConfiguration: configuration)
		let manager = try client.createRealtimeManager(
			options: RealtimeConfiguration(model: Models.realtime(.lucyVton3_5), speed: .fast)
		)
		let stored = manager.signalingServerURL.absoluteString
		XCTAssertEqual(stored, "wss://api.decart.ai/v1/stream?api_key=test-key&model=lucy-vton-3.5&speed=fast")
		XCTAssertEqual(occurrences(of: "speed=", in: stored), 1)
		XCTAssertEqual(manager.options.speed, .fast)
	}

	func testManagerStoresSignalingURLWithoutSpeedByDefault() throws {
		let client = DecartClient(decartConfiguration: configuration)
		let manager = try client.createRealtimeManager(options: RealtimeConfiguration(model: Models.realtime(.lucyLatest)))
		XCTAssertEqual(manager.signalingServerURL.absoluteString, "wss://api.decart.ai/v1/stream?api_key=test-key&model=lucy-latest")
		XCTAssertNil(manager.options.speed)
	}
}
