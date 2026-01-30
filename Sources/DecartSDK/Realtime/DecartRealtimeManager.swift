import Foundation
@preconcurrency import WebRTC

public final class DecartRealtimeManager: @unchecked Sendable {
	public let options: RealtimeConfiguration
	public let events: AsyncStream<DecartRealtimeConnectionState>

	private var webRTCClient: WebRTCClient?
	private var webSocketClient: WebSocketClient?

	private let signalingServerURL: URL
	private let stateContinuation: AsyncStream<DecartRealtimeConnectionState>.Continuation
	private var webSocketListenerTask: Task<Void, Never>?
	private var connectionStateListenerTask: Task<Void, Never>?
	private let setImageAckState = SetImageAckState()
	private let defaultImageSendTimeout: TimeInterval = 15

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
	}

	deinit {
		webSocketListenerTask?.cancel()
		connectionStateListenerTask?.cancel()
		webRTCClient?.close()
		Task { [setImageAckState] in
			await setImageAckState.cancel(error: DecartError.websocketError("Realtime manager deinitialized"))
		}
		stateContinuation.finish()
		DecartLogger.log("RealtimeManager (SDK) deinitialized", level: .info)
	}
}

// MARK: - Public API

public extension DecartRealtimeManager {
	func connect(localStream: RealtimeMediaStream) async throws -> RealtimeMediaStream {
		connectionState = .connecting

		let wsClient = await WebSocketClient(url: signalingServerURL)
		webSocketClient = wsClient
		setupWebSocketListener(wsClient)

		let rtcClient = WebRTCClient(
			config: options.connection.rtcConfiguration,
			constraints: options.media.connectionConstraints,
			videoConfig: options.media.video,
			sendMessage: { [weak self] in self?.sendMessage($0) },
			withAudio: localStream.audioTrack != nil
		)
		webRTCClient = rtcClient
		setupConnectionStateListener(rtcClient)

		rtcClient.startLocalStreaming(
			videoTrack: localStream.videoTrack,
			audioTrack: localStream.audioTrack
		)

		let offer = try await rtcClient.createOffer(constraints: options.media.offerConstraints)
		try await rtcClient.setLocalDescription(offer)
		sendMessage(.offer(OfferMessage(sdp: offer.sdp)))

		try await waitForConnection(timeout: options.connection.connectionTimeout)

		sendMessage(
			.prompt(PromptMessage(prompt: options.initialPrompt.text))
		)

		guard let remoteStream = rtcClient.getRemoteRealtimeStream() else {
			throw DecartError.webRTCError("couldn't get remote stream, check video transceiver")
		}

		return remoteStream
	}

	func disconnect() async {
		connectionState = .disconnected
		webSocketListenerTask?.cancel()
		webSocketListenerTask = nil
		connectionStateListenerTask?.cancel()
		connectionStateListenerTask = nil
		await setImageAckState.cancel(error: DecartError.websocketError("Realtime disconnected"))
		webRTCClient?.close()
		webRTCClient = nil
		await webSocketClient?.disconnect()

		#if canImport(WebRTC) && os(iOS)
		let audioSession = RTCAudioSession.sharedInstance()
		if audioSession.isActive {
			audioSession.lockForConfiguration()
			try? audioSession.setActive(false)
			audioSession.unlockForConfiguration()
		}
		#endif
		webSocketClient = nil
	}

	func setPrompt(_ prompt: DecartPrompt) {
		sendMessage(.prompt(PromptMessage(prompt: prompt.text)))
	}

	func setImageBase64(
		_ imageBase64: String?,
		prompt: String? = nil,
		enhance: Bool? = nil,
		timeout: TimeInterval? = nil
	) async throws {
		let timeoutSeconds = timeout ?? defaultImageSendTimeout
		let message = SetImageMessage(
			imageData: imageBase64,
			prompt: prompt,
			enhancePrompt: enhance
		)
		try await setImageAckState.send(
			message: message,
			timeout: timeoutSeconds,
			sendMessage: { [weak self] outgoing in
				self?.sendMessage(outgoing)
			}
		)
	}

	func waitForConnection(timeout: TimeInterval) async throws {
		let startTime = Date()
		while connectionState != .connected {
			if connectionState == .error || connectionState == .disconnected {
				throw DecartError.webRTCError("Connection failed")
			}
			if Date().timeIntervalSince(startTime) > timeout {
				throw DecartError.webRTCError("Connection timeout")
			}
			try await Task.sleep(nanoseconds: 100_000_000 * 100) // 100 seconds
		}
	}
}

// MARK: - Connection

public extension DecartRealtimeManager {
	func createVideoSource() -> RTCVideoSource {
		WebRTCClient.createVideoSource()
	}

	func replaceVideoTrack(with newTrack: RTCVideoTrack) {
		webRTCClient?.replaceVideoTrack(with: newTrack)
	}

	func createVideoTrack(source: RTCVideoSource, trackId: String) -> RTCVideoTrack {
		WebRTCClient.createVideoTrack(source: source, trackId: trackId)
	}

	func createAudioSource(constraints: RTCMediaConstraints? = nil) -> RTCAudioSource {
		WebRTCClient.createAudioSource(constraints: constraints)
	}

	func createAudioTrack(source: RTCAudioSource, trackId: String) -> RTCAudioTrack {
		WebRTCClient.createAudioTrack(source: source, trackId: trackId)
	}
}

// MARK: - Listeners

private extension DecartRealtimeManager {
	func setupWebSocketListener(_ wsClient: WebSocketClient) {
		webSocketListenerTask?.cancel()
		webSocketListenerTask = Task { [weak self] in
			do {
				for try await message in wsClient.websocketEventStream {
					guard !Task.isCancelled, let self, let webRTCClient = self.webRTCClient else { return }
					switch message {
					case .setImageAck(let ack):
						self.handleSetImageAck(ack)
					case .promptAck, .sessionId:
						break
					default:
						try await webRTCClient.handleSignalingMessage(message)
					}
				}
			} catch {
				self?.connectionState = .error
			}
		}
	}

	func setupConnectionStateListener(_ rtcClient: WebRTCClient) {
		connectionStateListenerTask?.cancel()
		connectionStateListenerTask = Task { [weak self] in
			for await rtcState in rtcClient.connectionStateStream {
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
}

// MARK: - Messaging

private extension DecartRealtimeManager {
	func sendMessage(_ message: OutgoingWebSocketMessage) {
		guard let webSocketClient else { return }
		Task { [webSocketClient] in try? await webSocketClient.send(message) }
	}

	func handleSetImageAck(_ message: SetImageAckMessage) {
		Task { [setImageAckState] in
			await setImageAckState.handleAck(message: message)
		}
	}
}

// MARK: - SetImageAckState Actor

private actor SetImageAckState {
	private var continuation: CheckedContinuation<Void, Error>?
	private var timeoutTask: Task<Void, Never>?

	func send(
		message: SetImageMessage,
		timeout: TimeInterval,
		sendMessage: (OutgoingWebSocketMessage) -> Void
	) async throws {
		guard continuation == nil else {
			throw DecartError.invalidOptions("setImageBase64 already in progress")
		}

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			self.continuation = continuation
			sendMessage(.setImage(message))

			timeoutTask?.cancel()
			timeoutTask = Task { [weak self] in
				try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
				await self?.timeout()
			}
		}
	}

	private func timeout() {
		guard let continuation else { return }
		self.continuation = nil
		timeoutTask = nil
		continuation.resume(
			throwing: DecartError.websocketError("Image send timed out")
		)
	}

	func handleAck(message: SetImageAckMessage) {
		guard let continuation = continuation else { return }
		self.continuation = nil
		timeoutTask?.cancel()
		timeoutTask = nil

		if message.success {
			continuation.resume()
		} else {
			continuation.resume(
				throwing: DecartError.serverError(message.error ?? "Failed to send image")
			)
		}
	}

	func cancel(error: Error) {
		guard let continuation = continuation else { return }
		self.continuation = nil
		timeoutTask?.cancel()
		timeoutTask = nil
		continuation.resume(throwing: error)
	}
}
