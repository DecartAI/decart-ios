import Foundation
@preconcurrency import WebRTC

public final class RealtimeManager: @unchecked Sendable {
	public let options: RealtimeConfiguration
	public let events: AsyncStream<DecartRealtimeConnectionState>

	let webRTCClient: WebRTCClient
	private var webSocketClient: WebSocketClient?

	private let signalingServerURL: URL
	private let stateContinuation: AsyncStream<DecartRealtimeConnectionState>.Continuation
	private var webSocketListenerTask: Task<Void, Never>?
	private var connectionStateListenerTask: Task<Void, Never>?

	private var connectionState: DecartRealtimeConnectionState = .idle {
		didSet {
			guard oldValue != connectionState else { return }
			stateContinuation.yield(connectionState)
		}
	}

	public init(signalingServerURL: URL, options: RealtimeConfiguration) {
		self.signalingServerURL = signalingServerURL
		self.options = options

		let (stream, continuation) = AsyncStream.makeStream(
			of: DecartRealtimeConnectionState.self,
			bufferingPolicy: .bufferingNewest(1)
		)
		self.events = stream
		self.stateContinuation = continuation
		self.webRTCClient = WebRTCClient()
	}

	// MARK: - Public API

	public func connect(localStream: RealtimeMediaStream) async throws -> RealtimeMediaStream {
		connectionState = .connecting

		let wsClient = WebSocketClient()
		webSocketClient = wsClient
		await wsClient.connect(url: signalingServerURL)
		setupWebSocketListener(wsClient)

		webRTCClient.createPeerConnection(
			config: options.connection.makeRTCConfiguration(),
			constraints: options.media.connectionConstraints,
			sendMessage: { [weak self] in self?.sendMessage($0) }
		)
		setupConnectionStateListener()

		webRTCClient.addTrack(localStream.videoTrack, streamIds: [localStream.id])
		if let audioTrack = localStream.audioTrack {
			webRTCClient.addTrack(audioTrack, streamIds: [localStream.id])
		}

		webRTCClient.configureVideoTransceiver(videoConfig: options.media.video)

		let offer = try await webRTCClient.createOffer(constraints: options.media.offerConstraints)
		try await webRTCClient.setLocalDescription(offer)
		sendMessage(.offer(OfferMessage(sdp: offer.sdp)))

		try await waitForConnection(timeout: TimeInterval(options.connection.connectionTimeout) / 1000)

		return try extractRemoteStream()
	}

	public func disconnect() async {
		await cleanup()
	}

	public func setPrompt(_ prompt: Prompt) {
		sendMessage(.prompt(PromptMessage(prompt: prompt.text)))
	}

	public func switchCamera(rotateY: Int) {
		sendMessage(.switchCamera(SwitchCameraMessage(rotateY: rotateY)))
	}

	// MARK: - Private

	private func waitForConnection(timeout: TimeInterval) async throws {
		let startTime = Date()
		while connectionState != .connected {
			if connectionState == .error || connectionState == .disconnected {
				throw DecartError.webRTCError("Connection failed")
			}
			if Date().timeIntervalSince(startTime) > timeout {
				throw DecartError.webRTCError("Connection timeout")
			}
			try await Task.sleep(nanoseconds: 100_000_000)
		}
		sendMessage(.prompt(PromptMessage(prompt: options.initialState.prompt.text)))
	}

	private func extractRemoteStream() throws -> RealtimeMediaStream {
		guard let videoTransceiver = webRTCClient.transceivers.first(where: { $0.mediaType == .video }) else {
			throw DecartError.webRTCError("Video transceiver not found")
		}
		guard let remoteVideoTrack = videoTransceiver.receiver.track as? RTCVideoTrack else {
			throw DecartError.webRTCError("Remote video track not found")
		}
		let remoteAudioTrack = webRTCClient.transceivers
			.first(where: { $0.mediaType == .audio })?
			.receiver.track as? RTCAudioTrack

		return RealtimeMediaStream(
			videoTrack: remoteVideoTrack,
			audioTrack: remoteAudioTrack,
			id: .remoteStream
		)
	}

	private func setupWebSocketListener(_ wsClient: WebSocketClient) {
		webSocketListenerTask?.cancel()
		webSocketListenerTask = Task { [weak self] in
			do {
				for try await message in wsClient.websocketEventStream {
					guard !Task.isCancelled, let self else { return }
					try await self.webRTCClient.handleSignalingMessage(message)
				}
			} catch {
				self?.connectionState = .error
			}
		}
	}

	private func setupConnectionStateListener() {
		connectionStateListenerTask?.cancel()
		guard let stateStream = webRTCClient.connectionStateStream else { return }
		connectionStateListenerTask = Task { [weak self] in
			for await rtcState in stateStream {
				guard !Task.isCancelled, let self else { return }
				switch rtcState {
				case .connected: self.connectionState = .connected
				case .failed, .closed, .disconnected: self.connectionState = .disconnected
				case .connecting where self.connectionState == .idle: self.connectionState = .connecting
				default: break
				}
			}
		}
	}

	private func sendMessage(_ message: OutgoingWebSocketMessage) {
		guard let webSocketClient else { return }
		Task { try? await webSocketClient.send(message) }
	}

	private func cleanup() async {
		connectionState = .disconnected
		webSocketListenerTask?.cancel()
		webSocketListenerTask = nil
		connectionStateListenerTask?.cancel()
		connectionStateListenerTask = nil
		webRTCClient.closePeerConnection()
		await webSocketClient?.disconnect()
		webSocketClient = nil
	}

	deinit {
		webSocketListenerTask?.cancel()
		connectionStateListenerTask?.cancel()
		webRTCClient.closePeerConnection()
		stateContinuation.finish()
	}
}
