import Foundation

public final class DecartRealtimeManager: @unchecked Sendable {
	public let options: RealtimeConfiguration
	public let events: AsyncStream<DecartRealtimeState>
	public let remoteStreamUpdates: AsyncStream<RealtimeMediaStream>
	public let diagnosticUpdates: AsyncStream<DecartRealtimeDiagnosticEvent>
	public let statsUpdates: AsyncStream<DecartRealtimeWebRTCStats>
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

	private var liveKitMediaChannel: LiveKitMediaChannel?
	private var webSocketClient: WebSocketClient?

	private let signalingServerURL: URL
	private let stateContinuation: AsyncStream<DecartRealtimeState>.Continuation
	private let remoteStreamContinuation: AsyncStream<RealtimeMediaStream>.Continuation
	private var webSocketListenerTask: Task<Void, Never>?
	private var mediaListenerTask: Task<Void, Never>?
	private var mediaConnectionStateTask: Task<Void, Never>?
	private var mediaDisconnectTask: Task<Void, Never>?
	private var mediaStatsTask: Task<Void, Never>?
	private var reconnectTask: Task<Void, Never>?
	private let initialStateAckTimeout: TimeInterval = 30
	private var reconnectAttempts: Int = 0
	private let maxReconnectAttempts: Int = 5
	private var isReconnecting = false
	private var isUserInitiatedDisconnect = false
	private var isPermanentError = false
	private var suppressMediaConnectedState = false
	private var lastLocalStream: RealtimeMediaStream?
	private let observability: RealtimeObservability

	private let roomInfoRequest = AsyncRequest<LiveKitRoomInfoMessage>()
	private let promptAckRequest = AsyncRequest<PromptAckMessage>()
	private let setImageAckRequest = AsyncRequest<SetImageAckMessage>()

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

	public init(
		signalingServerURL: URL,
		options: RealtimeConfiguration,
		apiKey: String = "",
		integration: String? = nil,
		telemetryEnabled: Bool = true
	) {
		self.signalingServerURL = signalingServerURL
		self.options = options
		self.observability = RealtimeObservability(
			apiKey: apiKey,
			model: options.model.name,
			integration: integration,
			telemetryEnabled: telemetryEnabled
		)
		self.diagnosticUpdates = observability.diagnosticUpdates
		self.statsUpdates = observability.statsUpdates

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

		DecartLiveKitLogging.install(observability: observability)
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
		mediaListenerTask?.cancel()
		mediaConnectionStateTask?.cancel()
		mediaDisconnectTask?.cancel()
		mediaStatsTask?.cancel()
		reconnectTask?.cancel()
		let liveKitMediaChannel = liveKitMediaChannel
		let webSocketClient = webSocketClient
		let observability = observability
		Task {
			await liveKitMediaChannel?.disconnect()
			await webSocketClient?.disconnect()
			await observability.finish()
		}
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
		connectionState = .connecting
		return try await connectWithRetry(localStream: localStream, isReconnectAttempt: false)
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
		resetPendingRequests()
		generationTick = nil
		sessionId = nil
		serviceStatus = .unknown
		queuePosition = nil
		queueSize = nil
		await closeRealtimeClients()
		await observability.stopTelemetry()
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

	func setPromptAndWait(_ prompt: DecartPrompt, timeout: TimeInterval? = nil) async throws {
		guard options.model.hasReferenceImage else {
			try await sendPromptAndWait(prompt, timeout: timeout ?? options.connection.requestTimeout)
			return
		}

		try await setImageAndWait(
			prompt.referenceImageData,
			prompt: prompt.text,
			enhance: prompt.enrich,
			timeout: timeout ?? options.connection.requestTimeout
		)
	}

	func setImageAndWait(
		_ imageData: Data?,
		prompt: String? = nil,
		enhance: Bool? = nil,
		timeout: TimeInterval? = nil
	) async throws {
		try await sendImageAndWait(
			imageData?.base64EncodedString(),
			prompt: prompt,
			enhance: enhance,
			timeout: timeout ?? options.connection.requestTimeout
		)
	}
}

private extension DecartRealtimeManager {
	func connectWithRetry(
		localStream: RealtimeMediaStream,
		isReconnectAttempt: Bool
	) async throws -> RealtimeMediaStream {
		let maxAttempts = max(options.connection.sessionRetryAttempts, maxReconnectAttempts)
		var attempt = 0
		var lastError: Error?

		while attempt <= maxAttempts {
			if Task.isCancelled || isUserInitiatedDisconnect {
				throw DecartError.webRTCError("Connection cancelled")
			}

			do {
				let stream = try await performConnect(
					localStream: localStream,
					isReconnectAttempt: isReconnectAttempt,
					attempt: attempt + 1
				)
				return stream
			} catch {
				lastError = error
				await closeRealtimeClients()

				if isPermanentError || Self.isPermanentErrorMessage(error.localizedDescription) || attempt >= maxAttempts {
					connectionState = isPermanentError ? .error : .disconnected
					observability.emitLog(
						"realtime connect failed permanently",
						level: .error,
						category: "realtime.connection",
						metadata: ["error": error.localizedDescription]
					)
					throw error
				}

				let delay = min(pow(2.0, Double(attempt)), 10.0)
				observability.emitLog(
					"realtime connect attempt failed; retrying",
					level: .warning,
					category: "realtime.connection",
					metadata: ["attempt": "\(attempt + 1)", "delay": "\(delay)", "error": error.localizedDescription]
				)
				attempt += 1
				connectionState = isReconnectAttempt ? .reconnecting : .connecting
				try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
			}
		}

		throw lastError ?? DecartError.webRTCError("Connection failed")
	}

	func performConnect(
		localStream: RealtimeMediaStream,
		isReconnectAttempt: Bool,
		attempt: Int
	) async throws -> RealtimeMediaStream {
		if !isReconnectAttempt {
			connectionState = .connecting
		}
		resetPendingRequests()
		generationTick = nil
		sessionId = nil

		await closeRealtimeClients()

		let websocketStart = Date()
		let wsClient: WebSocketClient
		do {
			wsClient = try await WebSocketClient(
				url: signalingServerURL,
				timeout: options.connection.signalingConnectTimeout
			)
			await observability.diagnostic(
				"client-session-connection-breakdown",
				data: [
					"attempt": .int(attempt),
					"phase": .string("websocket-open"),
					"durationMs": .int(Int(Date().timeIntervalSince(websocketStart) * 1000)),
					"success": .bool(true)
				]
			)
		} catch {
			await observability.diagnostic(
				"client-session-connection-breakdown",
				data: [
					"attempt": .int(attempt),
					"phase": .string("websocket-open"),
					"durationMs": .int(Int(Date().timeIntervalSince(websocketStart) * 1000)),
					"success": .bool(false),
					"errorType": .string(String(describing: type(of: error)))
				]
			)
			throw error
		}
		webSocketClient = wsClient
		setupWebSocketListener(wsClient)

		try await wsClient.send(OutgoingWebSocketMessage.liveKitJoin)
		let roomInfo = try await roomInfoRequest.wait(
			timeout: options.connection.roomInfoTimeout,
			timeoutError: DecartError.websocketError("LiveKit room info timed out")
		)

		let mediaChannel = LiveKitMediaChannel(
			videoPublishOptions: options.media.video.publishOptions,
			connectOptions: options.connection.connectOptions,
			roomOptions: options.connection.roomOptions,
			observability: observability
		)
		liveKitMediaChannel = mediaChannel
		setupMediaListeners(mediaChannel)

		let shouldWaitForInitialState = hasCallerProvidedInitialState()
		suppressMediaConnectedState = true
		async let initialStateAck: Void = sendInitialState()
		try await mediaChannel.connect(roomInfo: roomInfo)
		if shouldWaitForInitialState {
			try await initialStateAck
		} else {
			_ = try? await initialStateAck
		}
		try await mediaChannel.publishLocalTracks(from: localStream)
		suppressMediaConnectedState = false
		connectionState = .connected
		await observability.sessionStarted(roomInfo.sessionId)
		await observability.diagnostic(
			"client-session-connection-breakdown",
			data: [
				"attempt": .int(attempt),
				"success": .bool(true)
			]
		)
		return mediaChannel.currentRemoteStream
	}

	func closeRealtimeClients() async {
		webSocketListenerTask?.cancel()
		webSocketListenerTask = nil
		mediaListenerTask?.cancel()
		mediaListenerTask = nil
		mediaConnectionStateTask?.cancel()
		mediaConnectionStateTask = nil
		mediaDisconnectTask?.cancel()
		mediaDisconnectTask = nil
		mediaStatsTask?.cancel()
		mediaStatsTask = nil
		suppressMediaConnectedState = false
		await liveKitMediaChannel?.disconnect()
		liveKitMediaChannel = nil
		await webSocketClient?.disconnect()
		webSocketClient = nil
	}

	func resetPendingRequests() {
		roomInfoRequest.reset()
		promptAckRequest.reset()
		setImageAckRequest.reset()
	}

	func failPendingRequests(_ error: Error) {
		roomInfoRequest.fail(error)
		promptAckRequest.fail(error)
		setImageAckRequest.fail(error)
	}
}

// MARK: - Listeners

private extension DecartRealtimeManager {
	func setupWebSocketListener(_ wsClient: WebSocketClient) {
		webSocketListenerTask?.cancel()
		webSocketListenerTask = Task { [weak self] in
			for await message in wsClient.websocketEventStream {
				guard !Task.isCancelled, let self else { return }
				switch message {
				case .status(let status):
					self.serviceStatus = RealtimeServiceStatus.fromStatusString(status.status)
				case .queuePosition(let queue):
					self.queuePosition = queue.queuePosition
					self.queueSize = queue.queueSize
				case .liveKitRoomInfo(let roomInfo):
					self.sessionId = roomInfo.sessionId
					self.roomInfoRequest.fulfill(roomInfo)
				case .promptAck(let ack):
					self.promptAckRequest.fulfill(ack)
				case .setImageAck(let ack):
					self.setImageAckRequest.fulfill(ack)
				case .sessionId(let message):
					self.sessionId = message.id
				case .generationStarted:
					self.connectionState = .generating
					await self.observability.diagnostic("generationStarted", data: [:])
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
					if Self.isPermanentErrorMessage(errorText) {
						self.isPermanentError = true
					}
					self.failPendingRequests(error)
					self.observability.emitLog(
						"server error received",
						level: .error,
						category: "realtime.signaling",
						metadata: ["error": errorText]
					)
					self.connectionState = .error
				}
			}
			guard !Task.isCancelled else { return }
			let disconnectError = DecartError.websocketError("WebSocket disconnected")
			self?.failPendingRequests(disconnectError)
			self?.connectionState = .disconnected
			self?.handleUnexpectedDisconnect()
		}
	}

	func setupMediaListeners(_ mediaChannel: LiveKitMediaChannel) {
		mediaListenerTask?.cancel()
		mediaListenerTask = Task { [weak self] in
			for await stream in mediaChannel.remoteStreamUpdates {
				guard !Task.isCancelled, let self else { return }
				self.remoteStreamContinuation.yield(stream)
			}
		}

		mediaConnectionStateTask?.cancel()
		mediaConnectionStateTask = Task { [weak self] in
			for await state in mediaChannel.connectionStateUpdates {
				guard !Task.isCancelled, let self else { return }
				if state == .connected, self.suppressMediaConnectedState {
					continue
				}
				self.connectionState = state
				if state == .connected {
					self.reconnectAttempts = 0
					self.isReconnecting = false
				}
			}
		}

		mediaDisconnectTask?.cancel()
		mediaDisconnectTask = Task { [weak self] in
			for await disconnect in mediaChannel.disconnectUpdates {
				guard !Task.isCancelled, let self else { return }
				self.observability.emitLog(
					"LiveKit room disconnected",
					level: .warning,
					category: "livekit.room",
					metadata: ["reason": disconnect.reason ?? "unknown"]
				)
				self.connectionState = .disconnected
				self.handleUnexpectedDisconnect()
			}
		}

		mediaStatsTask?.cancel()
		mediaStatsTask = Task { [weak self] in
			for await stats in mediaChannel.statsUpdates {
				guard !Task.isCancelled, let self else { return }
				await self.observability.recordStats(stats)
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
			do {
				let newRemoteStream = try await self.connectWithRetry(localStream: localStream, isReconnectAttempt: true)
				self.remoteStreamContinuation.yield(newRemoteStream)
				self.reconnectAttempts = 0
				self.isReconnecting = false
				self.connectionState = .connected
			} catch {
				self.reconnectAttempts = self.maxReconnectAttempts
				self.isReconnecting = false
				self.connectionState = .error
				self.observability.emitLog(
					"realtime reconnect failed",
					level: .error,
					category: "realtime.connection",
					metadata: ["error": error.localizedDescription]
				)
			}
		}
	}
}

// MARK: - Messaging

private extension DecartRealtimeManager {
	private func sendMessage(_ message: OutgoingWebSocketMessage) {
		guard let webSocketClient else { return }
		Task { [webSocketClient] in try? await webSocketClient.send(message) }
	}

	func sendInitialState() async throws {
		let initialPrompt = options.initialPrompt
		if options.model.hasReferenceImage,
			let base64Image = initialPrompt.referenceImageData?.base64EncodedString()
		{
			try await sendImageAndWait(
				base64Image,
				prompt: initialPrompt.text,
				enhance: initialPrompt.enrich,
				timeout: initialStateAckTimeout,
				requiresConnected: false,
				failureMessage: "Failed to set initial image",
				timeoutMessage: "Initial image acknowledgment timed out"
			)
		} else if !initialPrompt.text.isEmpty {
			try await sendPromptAndWait(
				initialPrompt,
				timeout: initialStateAckTimeout,
				requiresConnected: false,
				timeoutMessage: "Initial prompt acknowledgment timed out"
			)
		} else {
			try await sendPassthrough()
		}
	}

	func hasCallerProvidedInitialState() -> Bool {
		let initialPrompt = options.initialPrompt
		return initialPrompt.referenceImageData != nil || !initialPrompt.text.isEmpty
	}

	func sendPromptAndWait(
		_ prompt: DecartPrompt,
		timeout: TimeInterval,
		requiresConnected: Bool = true,
		timeoutMessage: String = "Prompt acknowledgment timed out"
	) async throws {
		if requiresConnected, !connectionState.isConnected {
			throw DecartError.websocketError("Cannot send prompt while connection is \(connectionState.rawValue)")
		}
		guard let webSocketClient else {
			connectionState = .error
			throw DecartError.websocketError("WebSocket not connected")
		}

		promptAckRequest.reset()
		let message: OutgoingWebSocketMessage = .prompt(PromptMessage(prompt: prompt.text, enhancePrompt: prompt.enrich))
		try await webSocketClient.send(message)
		let ack = try await promptAckRequest.wait(
			timeout: timeout,
			timeoutError: DecartError.websocketError(timeoutMessage)
		)
		if ack.success != true {
			connectionState = .error
			throw DecartError.serverError(ack.error ?? "Failed to send prompt")
		}
	}

	func sendImageAndWait(
		_ imageBase64: String?,
		prompt: String?,
		enhance: Bool?,
		timeout: TimeInterval,
		requiresConnected: Bool = true,
		failureMessage: String = "Failed to send image",
		timeoutMessage: String = "Image acknowledgment timed out"
	) async throws {
		if requiresConnected, !connectionState.isConnected {
			throw DecartError.websocketError("Cannot send image while connection is \(connectionState.rawValue)")
		}
		guard let webSocketClient else {
			connectionState = .error
			throw DecartError.websocketError("WebSocket not connected")
		}

		setImageAckRequest.reset()
		let message = SetImageMessage(
			imageData: imageBase64,
			prompt: prompt,
			enhancePrompt: enhance
		)
		try await webSocketClient.send(OutgoingWebSocketMessage.setImage(message))
		let ack = try await setImageAckRequest.wait(
			timeout: timeout,
			timeoutError: DecartError.websocketError(timeoutMessage)
		)
		if ack.success != true {
			connectionState = .error
			throw DecartError.serverError(ack.error ?? failureMessage)
		}
	}

	func sendPassthrough() async throws {
		guard let webSocketClient else {
			connectionState = .error
			throw DecartError.websocketError("WebSocket not connected")
		}
		try await webSocketClient.send(OutgoingWebSocketMessage.setImage(.passthrough()))
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
