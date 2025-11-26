import Foundation
@preconcurrency import WebRTC

struct SignalingClient {
	private let peerConnection: RTCPeerConnection
	private let factory: RTCPeerConnectionFactory
	private let sendMessage: (OutgoingWebSocketMessage) -> Void

	init(
		peerConnection: RTCPeerConnection,
		factory: RTCPeerConnectionFactory,
		sendMessage: @escaping (OutgoingWebSocketMessage) -> Void
	) {
		self.peerConnection = peerConnection
		self.factory = factory
		self.sendMessage = sendMessage
	}

	func handleMessage(_ message: IncomingWebSocketMessage) async throws {
		switch message {
		case .offer(let msg):
			let sdp = RTCSessionDescription(type: .offer, sdp: msg.sdp)
			try await peerConnection.setRemoteDescription(sdp)
			let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
			guard let answer = try await peerConnection.answer(for: constraints) else {
				throw DecartError.webRTCError("Failed to create answer")
			}
			try await peerConnection.setLocalDescription(answer)
			sendMessage(.answer(AnswerMessage(type: "answer", sdp: answer.sdp)))

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

		case .error(let msg):
			throw DecartError.serverError(msg.message ?? msg.error ?? "Unknown server error")

		case .sessionId, .promptAck:
			break
		}
	}
}
