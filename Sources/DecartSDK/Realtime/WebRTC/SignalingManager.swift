import Foundation
@preconcurrency import WebRTC

/// Manages WebSocket signaling connection with AsyncStream-based message delivery
actor SignalingManager {
	private let webSocket: WebSocketService
	private let peerConnection: RTCPeerConnection
	private var wsListenerTask: Task<Void, Never>?

	init(pc: RTCPeerConnection) {
		peerConnection = pc
		webSocket = WebSocketService()
	}

	func connect(url: URL, timeout: TimeInterval = 30) async {
		await webSocket.connect(url: url)
		let task = Task {
			let eventStream = self.webSocket.websocketEventStream
			do {
				for try await event in eventStream {
					if Task.isCancelled { return }
					await self.handle(event)
				}
			} catch {
				print("error in signaling loop: \(error)")
			}
		}
		if wsListenerTask != nil {
			wsListenerTask?.cancel()
			wsListenerTask = nil
		}

		wsListenerTask = task
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
		wsListenerTask?.cancel()
		wsListenerTask = nil
	}
}
