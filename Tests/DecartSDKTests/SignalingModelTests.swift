import XCTest
@testable import DecartSDK

final class SignalingModelTests: XCTestCase {
	func testEncodesLiveKitJoinMessage() throws {
		let data = try JSONEncoder().encode(OutgoingWebSocketMessage.liveKitJoin)
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

		XCTAssertEqual(json["type"], "livekit_join")
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

	func testEncodesSetImageMessage() throws {
		let message = SetImageMessage(
			imageData: "base64-image",
			prompt: "fit the jacket",
			enhancePrompt: true
		)
		let data = try JSONEncoder().encode(OutgoingWebSocketMessage.setImage(message))
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

		XCTAssertEqual(json["type"] as? String, "set_image")
		XCTAssertEqual(json["image_data"] as? String, "base64-image")
		XCTAssertEqual(json["prompt"] as? String, "fit the jacket")
		XCTAssertEqual(json["enhance_prompt"] as? Bool, true)
	}

	func testEncodesObservabilityMessage() throws {
		let payload: DecartRealtimeJSONValue = .object([
			"kind": .string("instrumentation"),
			"name": .string("room-connected"),
			"timestamp": .int(123)
		])
		let data = try JSONEncoder().encode(OutgoingWebSocketMessage.observability(data: payload))
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
		let payloadJSON = try XCTUnwrap(json["data"] as? [String: Any])

		XCTAssertEqual(json["type"] as? String, "observability")
		XCTAssertEqual(payloadJSON["kind"] as? String, "instrumentation")
		XCTAssertEqual(payloadJSON["name"] as? String, "room-connected")
		XCTAssertEqual(payloadJSON["timestamp"] as? Int, 123)
	}

	func testEncodesPassthroughInitialStateWithNullPromptAndImage() throws {
		let data = try JSONEncoder().encode(OutgoingWebSocketMessage.setImage(.passthrough()))
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

		XCTAssertEqual(json["type"] as? String, "set_image")
		XCTAssertTrue(json["prompt"] is NSNull)
		XCTAssertTrue(json["image_data"] is NSNull)
	}

	func testUserAgentIncludesSwiftRuntime() {
		let userAgent = DecartUserAgent.build()

		XCTAssertTrue(userAgent.contains("decart-swift-sdk/"))
		XCTAssertTrue(userAgent.contains("lang/swift"))
		XCTAssertTrue(userAgent.contains("runtime/"))
	}
}
