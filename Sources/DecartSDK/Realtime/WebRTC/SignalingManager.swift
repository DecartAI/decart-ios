import Foundation
import WebRTC

/// Manages WebSocket signaling connection with AsyncStream-based message delivery
actor SignalingManager: WebSocketMessageHandler {
	private let webSocket = WebSocketService()
	private var isConnected: Bool = false
	private let peerConnection: RTCPeerConnection

	init(pc: RTCPeerConnection) {
		peerConnection = pc
		webSocket.messageHandler = self
	}

	func connect(url: URL, timeout: TimeInterval = 30) {
		webSocket.connect(url: url)
	}

	func handle(_ message: IncomingWebSocketMessage) async {
		do {
			switch message {
			case .offer(let msg):
				let sdp = RTCSessionDescription(type: .offer, sdp: msg.sdp)
				try await peerConnection.setRemoteDescription(sdp)

				let constraints = RTCMediaConstraints(
					mandatoryConstraints: nil,
					optionalConstraints: nil
				)

				guard let answer = try? await peerConnection.answer(for: constraints) else {
					print("[WebRTCConnection] Failed to create answer")
					throw DecartError.webRTCError("failed to create answer, check logs")
				}

				try await peerConnection.setLocalDescription(answer)
				await send(.answer(AnswerMessage(type: "answer", sdp: answer.sdp)))

			case .answer(let msg):
				let sdp = RTCSessionDescription(type: .answer, sdp: msg.sdp)
				try await peerConnection.setRemoteDescription(sdp)

			case .iceCandidate(let msg):
				let candidate = RTCIceCandidate(
					sdp: msg.candidate.candidate,
					sdpMLineIndex: msg.candidate.sdpMLineIndex,
					sdpMid: msg.candidate.sdpMid
				)
				try await peerConnection.add(candidate)
			}
		} catch {
			DecartLogger.log("error while handling websocket message: \(error)", level: .error)
		}
	}

	func send(_ message: OutgoingWebSocketMessage) async {
		do {
			try await webSocket.send(message)
		} catch {
			DecartLogger.log("error while sending websocket message: \(error)", level: .error)
		}
	}

	func disconnect() async {
		await webSocket.disconnect()
	}

	deinit { DecartLogger.log("SignalingManager deinit", level: .info) }
}
