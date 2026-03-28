import Foundation
@preconcurrency import WebRTC

public final class DecartRealtimeManager: @unchecked Sendable {
	public let options: RealtimeConfiguration
	public let events: AsyncStream<DecartRealtimeState>
	public let remoteStreamUpdates: AsyncStream<RealtimeMediaStream>
	public private(set) var serviceStatus: RealtimeServiceStatus = .unknown {
		didSet {
			guard oldValue != serviceStatus else { return }
			emitStateIfChanged()
		}
	}
	public private(set) var queuePosition: Int? {
		didSet {
			guard oldValue != queuePosition else { return }
			emitStateIfChanged()
		}
	}
	public private(set) var queueSize: Int? {
		didSet {
			guard oldValue != queueSize else { return }
			emitStateIfChanged()
		}
	}
	public private(set) var sessionId: String? {
		didSet {
			guard oldValue != sessionId else { return }
			emitStateIfChanged()
		}
	}
	public private(set) var generationTick: Double? {
		didSet {
			guard oldValue != generationTick else { return }
			emitStateIfChanged()
		}
	}

	private var webRTCClient: WebRTCClient?
	private var webSocketClient: WebSocketClient?

	private let signalingServerURL: URL
	private let stateContinuation: AsyncStream<DecartRealtimeState>.Continuation
	private let remoteStreamContinuation: AsyncStream<RealtimeMediaStream>.Continuation
	private var webSocketListenerTask: Task<Void, Never>?
	private var connectionStateListenerTask: Task<Void, Never>?
	private var reconnectTask: Task<Void, Never>?
	private let initialStateAckTimeout: TimeInterval = 30
	private var isWaitingForInitialStateAck = false
	private var pendingPromptAck: PromptAckMessage?
	private var pendingSetImageAck: SetImageAckMessage?
	private var pendingInitialStateError: Error?
	private var reconnectAttempts: Int = 0
	private let maxReconnectAttempts: Int = 5
	private var isReconnecting = false
	private var isUserInitiatedDisconnect = false
	private var isPermanentError = false
	private var lastLocalStream: RealtimeMediaStream?

	private var connectionState: DecartRealtimeConnectionState = .idle {
		didSet {
			guard oldValue != connectionState else { return }
			emitStateIfChanged()
		}
	}

	private var lastEmittedState: DecartRealtimeState?
	private var currentState: DecartRealtimeState {
		DecartRealtimeState(
			connectionState: connectionState,
			serviceStatus: serviceStatus,
			queuePosition: queuePosition,
			queueSize: queueSize,
			generationTick: generationTick,
			sessionId: sessionId
		)
	}

	public init(signalingServerURL: URL, options: RealtimeConfiguration) {
		self.signalingServerURL = signalingServerURL
		self.options = options

		let (stream, continuation) = AsyncStream.makeStream(
			of: DecartRealtimeState.self,
			bufferingPolicy: .bufferingNewest(1)
		)
		self.events = stream
		self.stateContinuation = continuation

		let (remoteStream, remoteContinuation) = AsyncStream.makeStream(
			of: RealtimeMediaStream.self,
			bufferingPolicy: .bufferingNewest(1)
		)
		self.remoteStreamUpdates = remoteStream
		self.remoteStreamContinuation = remoteContinuation

		emitStateIfChanged()
	}

	private func emitStateIfChanged() {
		let state = currentState
		if lastEmittedState != state {
			lastEmittedState = state
			stateContinuation.yield(state)
		}
	}

	deinit {
		webSocketListenerTask?.cancel()
		connectionStateListenerTask?.cancel()
		reconnectTask?.cancel()
		webRTCClient?.close()
		stateContinuation.finish()
		remoteStreamContinuation.finish()
		DecartLogger.log("RealtimeManager (SDK) deinitialized", level: .info)
	}
}

// MARK: - Public API

public extension DecartRealtimeManager {
	func connect(localStream: RealtimeMediaStream) async throws -> RealtimeMediaStream {
		isUserInitiatedDisconnect = false
		isPermanentError = false
		reconnectTask?.cancel()
		reconnectTask = nil
		isReconnecting = false
		reconnectAttempts = 0
		lastLocalStream = localStream
		return try await performConnect(localStream: localStream, isReconnectAttempt: false)
	}

	func disconnect() async {
		isUserInitiatedDisconnect = true
		isPermanentError = false
		isReconnecting = false
		reconnectTask?.cancel()
		reconnectTask = nil
		reconnectAttempts = 0
		lastLocalStream = nil
		connectionState = .disconnected
		isWaitingForInitialStateAck = false
		clearPendingInitialState()
		generationTick = nil
		sessionId = nil
		serviceStatus = .unknown
		queuePosition = nil
		queueSize = nil
		await closeRealtimeClients()

		#if canImport(WebRTC) && os(iOS)
		let audioSession = RTCAudioSession.sharedInstance()
		if audioSession.isActive {
			audioSession.lockForConfiguration()
			try? audioSession.setActive(false)
			audioSession.unlockForConfiguration()
		}
		#endif
	}

	func setPrompt(_ prompt: DecartPrompt) {
		guard options.model.hasReferenceImage else {
			sendMessage(.prompt(PromptMessage(prompt: prompt.text, enhancePrompt: prompt.enrich)))
			return
		}

		let base64Image = prompt.referenceImageData?.base64EncodedString()
		sendImageWithPrompt(
			base64Image,
			prompt: prompt.text,
			enhance: prompt.enrich
		)
	}

	func waitForConnection(timeout: TimeInterval) async throws {
		let startTime = Date()
		while connectionState != .connected && connectionState != .generating {
			if connectionState == .error || connectionState == .disconnected {
				throw DecartError.webRTCError("Connection failed")
			}
			if Date().timeIntervalSince(startTime) > timeout {
				throw DecartError.webRTCError("Connection timeout")
			}
			try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
		}
	}

}

private extension DecartRealtimeManager {
	func performConnect(
		localStream: RealtimeMediaStream,
		isReconnectAttempt: Bool
	) async throws -> RealtimeMediaStream {
		if !isReconnectAttempt {
			connectionState = .connecting
		}
		clearPendingInitialState()
		generationTick = nil
		sessionId = nil

		await closeRealtimeClients()

		let wsClient = await WebSocketClient(url: signalingServerURL)
		webSocketClient = wsClient
		setupWebSocketListener(wsClient)

		if serviceStatus == .enteringQueue {
			try await waitForServiceReady()
		}

		try await sendInitialState()

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
		try await sendMessageThrowing(.offer(OfferMessage(sdp: offer.sdp)))

		try await waitForConnection(timeout: options.connection.connectionTimeout)

		guard let remoteStream = rtcClient.getRemoteRealtimeStream() else {
			throw DecartError.webRTCError("couldn't get remote stream, check video transceiver")
		}

		return remoteStream
	}

	func closeRealtimeClients() async {
		webSocketListenerTask?.cancel()
		webSocketListenerTask = nil
		connectionStateListenerTask?.cancel()
		connectionStateListenerTask = nil
		webRTCClient?.close()
		webRTCClient = nil
		await webSocketClient?.disconnect()
		webSocketClient = nil
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
					guard !Task.isCancelled, let self else { return }
					switch message {
					case .status(let status):
						self.serviceStatus = RealtimeServiceStatus.fromStatusString(status.status)
					case .queuePosition(let queue):
						self.queuePosition = queue.queuePosition
						self.queueSize = queue.queueSize
					case .promptAck(let ack):
						self.recordPromptAck(ack)
					case .setImageAck(let ack):
						self.recordSetImageAck(ack)
					case .sessionId(let message):
						self.sessionId = message.id
					case .generationStarted:
						self.connectionState = .generating
					case .generationTick(let tick):
						self.generationTick = tick.seconds
					case .generationEnded(let ended):
						if let seconds = ended.seconds {
							self.generationTick = seconds
						}
						if self.connectionState != .disconnected && self.connectionState != .error {
							self.connectionState = .connected
						}
					case .error(let errorMessage):
						let errorText = errorMessage.message ?? errorMessage.error ?? "Unknown server error"
						let error = DecartError.serverError(errorText)
						if DecartRealtimeManager.isPermanentErrorMessage(errorText) {
							self.isPermanentError = true
						}
						self.recordInitialStateError(error)
						if let webRTCClient = self.webRTCClient {
							try await webRTCClient.handleSignalingMessage(message)
						} else {
							self.connectionState = .error
						}
					default:
						guard let webRTCClient = self.webRTCClient else { break }
						try await webRTCClient.handleSignalingMessage(message)
					}
				}
				guard !Task.isCancelled else { return }
				self?.recordInitialStateError(DecartError.websocketError("WebSocket disconnected"))
				self?.connectionState = .disconnected
				self?.handleUnexpectedDisconnect()
			} catch {
				guard !Task.isCancelled else { return }
				self?.recordInitialStateError(error)
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
				case .connected:
					self.connectionState = .connected
					self.reconnectAttempts = 0
					self.isReconnecting = false
				case .disconnected, .failed:
					self.connectionState = .disconnected
					self.handleUnexpectedDisconnect()
				case .closed:
					self.connectionState = .disconnected
				case .connecting: self.connectionState = .connecting
				default: break
				}
			}
		}
	}
}

// MARK: - Service Status

private extension DecartRealtimeManager {
	static func isPermanentErrorMessage(_ message: String) -> Bool {
		let lowered = message.lowercased()
		return lowered.contains("401")
			|| lowered.contains("403")
			|| lowered.contains("unauthorized")
			|| lowered.contains("permission denied")
			|| lowered.contains("invalid api key")
			|| lowered.contains("invalid session")
			|| lowered.contains("session expired")
	}

	func handleUnexpectedDisconnect() {
		guard !isUserInitiatedDisconnect, !isPermanentError else { return }
		scheduleReconnectIfNeeded()
	}

	func scheduleReconnectIfNeeded() {
		guard !isReconnecting else { return }
		guard reconnectAttempts < maxReconnectAttempts else {
			connectionState = .error
			return
		}
		guard let localStream = lastLocalStream else {
			connectionState = .error
			return
		}

		isReconnecting = true
		connectionState = .reconnecting
		reconnectTask?.cancel()
		reconnectTask = Task { [weak self] in
			guard let self else { return }

			while !Task.isCancelled && !self.isUserInitiatedDisconnect && self.reconnectAttempts < self.maxReconnectAttempts {
				let delay = min(pow(2.0, Double(self.reconnectAttempts)), 10.0)
				do {
					try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
					guard !Task.isCancelled, !self.isUserInitiatedDisconnect else { return }
					let newRemoteStream = try await self.performConnect(localStream: localStream, isReconnectAttempt: true)
					self.remoteStreamContinuation.yield(newRemoteStream)
					self.reconnectAttempts = 0
					self.isReconnecting = false
					self.connectionState = .connected
					return
				} catch {
					self.reconnectAttempts += 1
					if self.reconnectAttempts >= self.maxReconnectAttempts {
						self.isReconnecting = false
						self.connectionState = .error
						return
					}
					self.connectionState = .reconnecting
				}
			}

			self.isReconnecting = false
		}
	}

	func waitForServiceReady() async throws {
		while serviceStatus == .enteringQueue {
			try await Task.sleep(nanoseconds: 3_000_000_000)
		}
	}
}

// MARK: - Messaging

private extension DecartRealtimeManager {
	private func sendMessage(_ message: OutgoingWebSocketMessage) {
		guard let webSocketClient else { return }
		Task { [webSocketClient] in try? await webSocketClient.send(message) }
	}

	private func sendMessageThrowing(_ message: OutgoingWebSocketMessage) async throws {
		guard let webSocketClient else {
			throw DecartError.websocketError("WebSocket not connected")
		}
		try await webSocketClient.send(message)
	}

	func sendInitialState() async throws {
		let initialPrompt = options.initialPrompt
		if options.model.hasReferenceImage,
			let base64Image = initialPrompt.referenceImageData?.base64EncodedString()
		{
			try await sendInitialImageAndWait(
				base64Image,
				prompt: initialPrompt.text,
				enhance: initialPrompt.enrich
			)
		} else if !initialPrompt.text.isEmpty {
			try await sendInitialPromptAndWait(initialPrompt)
		} else {
			try await sendPassthroughAndWait()
		}
	}

	func sendInitialPromptAndWait(_ prompt: DecartPrompt) async throws {
		guard let webSocketClient else {
			connectionState = .error
			throw DecartError.websocketError("WebSocket not connected")
		}

		clearPendingInitialState()
		isWaitingForInitialStateAck = true
		defer {
			isWaitingForInitialStateAck = false
			clearPendingInitialState()
		}

		let message: OutgoingWebSocketMessage = .prompt(PromptMessage(prompt: prompt.text, enhancePrompt: prompt.enrich))
		try await webSocketClient.send(message)
		try await waitForPromptAck(prompt: prompt.text, timeout: initialStateAckTimeout)
	}

	func sendInitialImageAndWait(
		_ imageBase64: String,
		prompt: String,
		enhance: Bool
	) async throws {
		guard let webSocketClient else {
			connectionState = .error
			throw DecartError.websocketError("WebSocket not connected")
		}

		clearPendingInitialState()
		isWaitingForInitialStateAck = true
		defer {
			isWaitingForInitialStateAck = false
			clearPendingInitialState()
		}

		let message = SetImageMessage(
			imageData: imageBase64,
			prompt: prompt,
			enhancePrompt: enhance
		)
		let outgoing: OutgoingWebSocketMessage = .setImage(message)
		try await webSocketClient.send(outgoing)
		try await waitForSetImageAck(
			timeout: initialStateAckTimeout,
			failureMessage: "Failed to set initial image",
			timeoutMessage: "Initial image acknowledgment timed out"
		)
	}

	func sendPassthroughAndWait() async throws {
		guard let webSocketClient else {
			connectionState = .error
			throw DecartError.websocketError("WebSocket not connected")
		}

		clearPendingInitialState()
		isWaitingForInitialStateAck = true
		defer {
			isWaitingForInitialStateAck = false
			clearPendingInitialState()
		}

		let passthrough: OutgoingWebSocketMessage = .setImage(.passthrough())
		try await webSocketClient.send(passthrough)
		try await waitForSetImageAck(
			timeout: initialStateAckTimeout,
			failureMessage: "Failed to apply initial passthrough state",
			timeoutMessage: "Initial passthrough acknowledgment timed out"
		)
	}

	func waitForPromptAck(prompt: String, timeout: TimeInterval) async throws {
		let startTime = Date()
		while true {
			if connectionState == .disconnected {
				throw DecartError.websocketError("Disconnected during initial state setup")
			}

			if let error = pendingInitialStateError {
				connectionState = .error
				throw error
			}

			if let ack = pendingPromptAck,
				ack.prompt == nil || ack.prompt == prompt
			{
				pendingPromptAck = nil
				guard ack.success == true else {
					connectionState = .error
					throw DecartError.serverError(ack.error ?? "Failed to send initial prompt")
				}
				return
			}

			if Date().timeIntervalSince(startTime) > timeout {
				connectionState = .error
				throw DecartError.websocketError("Initial prompt acknowledgment timed out")
			}

			try await Task.sleep(nanoseconds: 100_000_000)
		}
	}

	func waitForSetImageAck(
		timeout: TimeInterval,
		failureMessage: String,
		timeoutMessage: String
	) async throws {
		let startTime = Date()
		while true {
			if connectionState == .disconnected {
				throw DecartError.websocketError("Disconnected during initial state setup")
			}

			if let error = pendingInitialStateError {
				connectionState = .error
				throw error
			}

			if let ack = pendingSetImageAck {
				pendingSetImageAck = nil
				guard ack.success == true else {
					connectionState = .error
					throw DecartError.serverError(ack.error ?? failureMessage)
				}
				return
			}

			if Date().timeIntervalSince(startTime) > timeout {
				connectionState = .error
				throw DecartError.websocketError(timeoutMessage)
			}

			try await Task.sleep(nanoseconds: 100_000_000)
		}
	}

	func recordPromptAck(_ ack: PromptAckMessage) {
		guard isWaitingForInitialStateAck else { return }
		pendingPromptAck = ack
	}

	func recordSetImageAck(_ ack: SetImageAckMessage) {
		guard isWaitingForInitialStateAck else { return }
		pendingSetImageAck = ack
	}

	func recordInitialStateError(_ error: Error) {
		guard isWaitingForInitialStateAck else { return }
		pendingInitialStateError = error
	}

	func clearPendingInitialState() {
		pendingPromptAck = nil
		pendingSetImageAck = nil
		pendingInitialStateError = nil
	}

	func sendImageWithPrompt(
		_ imageBase64: String?,
		prompt: String,
		enhance: Bool
	) {
		let message = SetImageMessage(
			imageData: imageBase64,
			prompt: prompt,
			enhancePrompt: enhance
		)
		sendMessage(.setImage(message))
	}
}
