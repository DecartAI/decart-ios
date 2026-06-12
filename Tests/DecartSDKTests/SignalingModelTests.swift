import XCTest
@testable import DecartSDK

final class SignalingModelTests: XCTestCase {
	func testEncodesLiveKitJoinMessageWithNullInitialState() throws {
		let data = try JSONEncoder().encode(OutgoingWebSocketMessage.liveKitJoin(
			initialState: nil,
			encodesInitialState: true
		))
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

		XCTAssertEqual(json["type"] as? String, "livekit_join")
		XCTAssertTrue(json["initial_state"] is NSNull)
	}

	func testEncodesLiveKitJoinMessageWithBundledInitialState() throws {
		let data = try JSONEncoder().encode(OutgoingWebSocketMessage.liveKitJoin(
			initialState: .setImage(SetImageMessage(
				imageData: "base64-image",
				prompt: "wear the jacket",
				enhancePrompt: true
			)),
			encodesInitialState: true
		))
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
		let initialState = try XCTUnwrap(json["initial_state"] as? [String: Any])

		XCTAssertEqual(json["type"] as? String, "livekit_join")
		XCTAssertEqual(initialState["type"] as? String, "set_image")
		XCTAssertEqual(initialState["image_data"] as? String, "base64-image")
		XCTAssertEqual(initialState["prompt"] as? String, "wear the jacket")
		XCTAssertEqual(initialState["enhance_prompt"] as? Bool, true)
	}

	func testEncodesLegacyLiveKitJoinMessageWithoutInitialStateField() throws {
		let data = try JSONEncoder().encode(OutgoingWebSocketMessage.liveKitJoin(
			initialState: nil,
			encodesInitialState: false
		))
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

		XCTAssertEqual(json["type"] as? String, "livekit_join")
		XCTAssertNil(json["initial_state"])
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
