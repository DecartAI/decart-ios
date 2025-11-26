import Foundation
@preconcurrency import WebRTC

final class WebRTCDelegateHandler: NSObject {
	private let sendMessage: (OutgoingWebSocketMessage) -> Void
	private let connectionStateContinuation: AsyncStream<RTCPeerConnectionState>.Continuation

	init(
		sendMessage: @escaping (OutgoingWebSocketMessage) -> Void,
		connectionStateContinuation: AsyncStream<RTCPeerConnectionState>.Continuation
	) {
		self.sendMessage = sendMessage
		self.connectionStateContinuation = connectionStateContinuation
	}

	func cleanup() {
		connectionStateContinuation.finish()
	}
}

extension WebRTCDelegateHandler: RTCPeerConnectionDelegate {
	func peerConnection(
		_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState
	) {}

	func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

	func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

	func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

	func peerConnection(
		_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState
	) {}

	func peerConnection(
		_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState
	) {}

	func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
		sendMessage(.iceCandidate(IceCandidateMessage(candidate: candidate)))
	}

	func peerConnection(
		_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]
	) {}

	func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

	func peerConnection(
		_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState
	) {
		connectionStateContinuation.yield(newState)
	}
}

extension WebRTCDelegateHandler: @unchecked Sendable {}
