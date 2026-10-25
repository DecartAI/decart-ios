import XCTest
@testable import DecartSDK

final class SignalingModelTests: XCTestCase {
	func testEncodesLeanLiveKitJoinWithPassthroughFalse() throws {
		let data = try JSONEncoder().encode(OutgoingWebSocketMessage.liveKitJoin(passthrough: false))
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

		XCTAssertEqual(json["type"] as? String, "livekit_join")
		XCTAssertEqual(json["passthrough"] as? Bool, false)
		XCTAssertNil(json["initial_state"], "join must be lean — no nested initial state")
	}

	func testEncodesLeanLiveKitJoinWithPassthroughTrue() throws {
		let data = try JSONEncoder().encode(OutgoingWebSocketMessage.liveKitJoin(passthrough: true))
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

		XCTAssertEqual(json["type"] as? String, "livekit_join")
		XCTAssertEqual(json["passthrough"] as? Bool, true)
		XCTAssertEqual(json.count, 2, "join carries only type + passthrough")
	}

	// MARK: - passthrough derivation

	private func makeManager(
		hasReferenceImage: Bool = false,
		initialPrompt: DecartPrompt = .init(text: ""),
		passthroughOverride: Bool? = nil
	) -> DecartRealtimeManager {
		let model = ModelDefinition(
			name: "test-model",
			urlPath: "/v1/test",
			fps: 24,
			width: 512,
			height: 512,
			hasReferenceImage: hasReferenceImage
		)
		return DecartRealtimeManager(
			signalingServerURL: URL(string: "wss://example.test")!,
			options: RealtimeConfiguration(
				model: model,
				initialPrompt: initialPrompt,
				connection: .init(passthrough: passthroughOverride)
			)
		)
	}

	func testPassthroughTrueWhenNoInitialReference() {
		XCTAssertTrue(makeManager().test_isPassthrough)
	}

	func testPassthroughFalseWhenPromptSet() {
		XCTAssertFalse(makeManager(initialPrompt: .init(text: "a city")).test_isPassthrough)
	}

	func testPassthroughFalseWhenReferenceImageSet() {
		let manager = makeManager(
			hasReferenceImage: true,
			initialPrompt: .init(text: "", referenceImageData: Data([0x1, 0x2]))
		)
		XCTAssertFalse(manager.test_isPassthrough)
	}

	func testReferenceImageIgnoredWhenModelHasNoReferenceSupport() {
		let manager = makeManager(
			hasReferenceImage: false,
			initialPrompt: .init(text: "", referenceImageData: Data([0x1, 0x2]))
		)
		XCTAssertTrue(manager.test_isPassthrough)
	}

	func testExplicitPassthroughOverridesDerivation() {
		XCTAssertTrue(makeManager(initialPrompt: .init(text: "a city"), passthroughOverride: true).test_isPassthrough)
		XCTAssertFalse(makeManager(passthroughOverride: false).test_isPassthrough)
	}

	func testDecodesLiveKitRoomInfoMessage() throws {
		let payload = """
		{
		  "type": "livekit_room_info",
		  "livekit_url": "wss://livekit.example.com",
		  "token": "token-123",
		  "room_name": "room-123",
		  "session_id": "session-123"
		}
		""".data(using: .utf8)!

		let message = try JSONDecoder().decode(IncomingWebSocketMessage.self, from: payload)

		guard case let .liveKitRoomInfo(roomInfo) = message else {
			return XCTFail("Expected livekit_room_info message")
		}

		XCTAssertEqual(roomInfo.liveKitURL, "wss://livekit.example.com")
		XCTAssertEqual(roomInfo.token, "token-123")
		XCTAssertEqual(roomInfo.roomName, "room-123")
		XCTAssertEqual(roomInfo.sessionId, "session-123")
	}
}
