import Foundation
@preconcurrency import WebRTC

/// Manages WebSocket signaling connection with AsyncStream-based message delivery
actor SignalingManager {
	private let webSocket: WebSocketClient
	private let peerConnection: RTCPeerConnection
	private var wsListenerTask: Task<Void, Never>?

	private var state: DecartRealtimeConnectionState = .idle {
		didSet {
			guard oldValue != state else { return }
			stateContinuation.yield(state)
		}
	}

	private let stateContinuation: AsyncStream<DecartRealtimeConnectionState>.Continuation
	nonisolated let events: AsyncStream<DecartRealtimeConnectionState>

	init(pc: RTCPeerConnection) {
		peerConnection = pc
		webSocket = WebSocketClient()
		let (stream, continuation) = AsyncStream.makeStream(
			of: DecartRealtimeConnectionState.self,
			bufferingPolicy: .bufferingNewest(1)
		)
		events = stream
		stateContinuation = continuation
	}

	func connect(url: URL, timeout: TimeInterval = 30) async {
		state = .connecting
		await webSocket.connect(url: url)
		let task = Task {
			let eventStream = self.webSocket.websocketEventStream
			do {
				for try await event in eventStream {
					if Task.isCancelled { return }
					await self.handle(event)
				}
			} catch {
				DecartLogger.log("error in signaling loop: \(error)", level: .error)
				self.state = .error
			}
		}
		if wsListenerTask != nil {
			wsListenerTask?.cancel()
			wsListenerTask = nil
		}

		wsListenerTask = task
	}

	func updatePeerConnectionState(_ newState: RTCPeerConnectionState) {
		switch newState {
		case .connected:
			state = .connected
		case .failed, .closed:
			state = .disconnected
		case .connecting:
			// Keep as connecting if we are already there, or set it if we were idle
			if state != .connecting, state != .connected {
				state = .connecting
			}
		case .disconnected:
			state = .disconnected
		case .new:
			break  // Initial state, usually
		@unknown default:
			break
		}
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
					DecartLogger.log("[WebRTCConnection] Failed to create answer", level: .error)
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

	nonisolated func send(_ message: OutgoingWebSocketMessage) {
		Task {
			do {
				try await webSocket.send(message)
			} catch {
				DecartLogger.log("error while sending websocket message: \(error)", level: .error)
			}
		}
	}

	func disconnect() async {
		state = .disconnected
		await webSocket.disconnect()
		wsListenerTask?.cancel()
		wsListenerTask = nil
	}
}
