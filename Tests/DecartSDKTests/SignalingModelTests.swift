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
}
