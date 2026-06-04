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
	private var lastPreferedCodec: RealtimeVideoCodec?
	private let observability: RealtimeObservability

	private let roomInfoRequest = AsyncRequest<LiveKitRoomInfoMessage>()
	private let promptAckRequests = PromptAckRequests()
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

	public convenience init(
		signalingServerURL: URL,
		options: RealtimeConfiguration
	) {
		self.init(
			signalingServerURL: signalingServerURL,
			options: options,
			observability: RealtimeObservability(
				apiKey: nil,
				model: options.model.name,
				telemetryEnabled: false
			)
		)
	}

	init(
		signalingServerURL: URL,
		options: RealtimeConfiguration,
		observability: RealtimeObservability
	) {
		self.signalingServerURL = signalingServerURL
		self.options = options
		self.observability = observability
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

		DecartLiveKitLogging.install()
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

private actor PromptAckRequests {
	private var requests: [String: AsyncRequest<PromptAckMessage>] = [:]

	func prepare(prompt: String) -> AsyncRequest<PromptAckMessage> {
		if let existing = requests[prompt] {
			existing.reset(error: DecartError.serverError("superseded"))
		}
		let request = AsyncRequest<PromptAckMessage>()
		requests[prompt] = request
		return request
	}

	func fulfill(_ ack: PromptAckMessage) {
		guard
			let prompt = ack.prompt,
			let request = requests.removeValue(forKey: prompt)
		else { return }
		request.fulfill(ack)
	}

	func cancel(prompt: String, request: AsyncRequest<PromptAckMessage>, error: Error) {
		guard requests[prompt] === request else { return }
		requests[prompt] = nil
		request.fail(error)
	}

	func resetAll() {
		let pending = requests.values
		requests.removeAll()
		for request in pending {
			request.reset()
		}
	}

	func failAll(_ error: Error) {
		let pending = requests.values
		requests.removeAll()
		for request in pending {
			request.fail(error)
		}
	}
}

// MARK: - Public API

public extension DecartRealtimeManager {
	func connect(
		localStream: RealtimeMediaStream,
		preferedCodec: RealtimeVideoCodec = .vp9
	) async throws -> RealtimeMediaStream {
		isUserInitiatedDisconnect = false
		isPermanentError = false
		reconnectTask?.cancel()
		reconnectTask = nil
		isReconnecting = false
		reconnectAttempts = 0
		lastLocalStream = localStream
		lastPreferedCodec = preferedCodec
		connectionState = .connecting
		return try await connectWithRetry(
			localStream: localStream,
			preferedCodec: preferedCodec,
			isReconnectAttempt: false
		)
	}

	func disconnect() async {
		isUserInitiatedDisconnect = true
		isPermanentError = false
		isReconnecting = false
		reconnectTask?.cancel()
		reconnectTask = nil
		reconnectAttempts = 0
		lastLocalStream = nil
		lastPreferedCodec = nil
		connectionState = .disconnected
		await resetPendingRequests()
		generationTick = nil
		sessionId = nil
		serviceStatus = .unknown
		queuePosition = nil
		queueSize = nil
		await closeRealtimeClients()
		await observability.flushPendingIfNeeded()
		await observability.stopTelemetry()
	}

	func setPrompt(_ prompt: DecartPrompt) async throws {
		guard options.model.hasReferenceImage else {
			try await sendPromptAndWait(prompt, timeout: options.connection.requestTimeout)
			return
		}

		try await sendImageAndWait(
			prompt.referenceImageData?.base64EncodedString(),
			prompt: prompt.text,
			enhance: prompt.enrich,
			timeout: options.connection.requestTimeout
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
			try await Task.sleep(nanoseconds: 1_000_000_000)
		}
	}
}

private extension DecartRealtimeManager {
	func connectWithRetry(
		localStream: RealtimeMediaStream,
		preferedCodec: RealtimeVideoCodec,
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
					preferedCodec: preferedCodec,
					isReconnectAttempt: isReconnectAttempt,
					attempt: attempt + 1
				)
				return stream
			} catch {
				lastError = error
				await closeRealtimeClients()

				if isPermanentError || Self.isPermanentErrorMessage(error.localizedDescription) || attempt >= maxAttempts {
					connectionState = isPermanentError ? .error : .disconnected
					await observability.recordLog(
						"realtime connect failed permanently",
						level: .error,
						category: "realtime.connection",
						metadata: connectionLogMetadata(
							attempt: attempt + 1,
							isReconnectAttempt: isReconnectAttempt,
							error: error
						)
					)
					await observability.flushPendingIfNeeded()
					throw error
				}

				let delay = min(pow(2.0, Double(attempt)), 10.0)
				var retryMetadata = connectionLogMetadata(
					attempt: attempt + 1,
					isReconnectAttempt: isReconnectAttempt,
					error: error
				)
				retryMetadata["delaySeconds"] = "\(delay)"
				observability.emitLog(
					"realtime connect attempt failed; retrying",
					level: .warning,
					category: "realtime.connection",
					metadata: retryMetadata
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
		preferedCodec: RealtimeVideoCodec,
		isReconnectAttempt: Bool,
		attempt: Int
	) async throws -> RealtimeMediaStream {
		if !isReconnectAttempt {
			connectionState = .connecting
		}
		await resetPendingRequests()
		generationTick = nil
		sessionId = nil

		await closeRealtimeClients()
		await observability.beginConnectionBreakdown(
			attempt: attempt,
			initialImageSizeKb: initialImageSizeKb()
		)

		do {
			let wsClient = try await openSignalingPhase()
			webSocketClient = wsClient
			await observability.setObservabilityForwarder { [wsClient] payload in
				await wsClient.sendBestEffort(OutgoingWebSocketMessage.observability(data: payload))
			}
			await observability.startNetworkMonitoring()
			setupWebSocketListener(wsClient)

			let roomInfo = try await joinRoomPhase(wsClient)

			let mediaChannel = LiveKitMediaChannel(
				videoPublishOptions: options.media.video.makePublishOptions(preferedCodec: preferedCodec),
				connectOptions: options.connection.connectOptions,
				observability: observability
			)
			liveKitMediaChannel = mediaChannel
			setupMediaListeners(mediaChannel)

			let shouldWaitForInitialState = hasCallerProvidedInitialState()
			suppressMediaConnectedState = true
			await observability.startPhase("initial-state-handshake")
			async let initialStateAck: Void = sendInitialState()

			await observability.startPhase("webrtc-handshake")
			do {
				try await mediaChannel.connect(roomInfo: roomInfo)
				await observability.endPhase("webrtc-handshake", success: true)
			} catch {
				await observability.endPhase("webrtc-handshake", success: false, error: error.localizedDescription)
				throw error
			}

			do {
				if shouldWaitForInitialState {
					try await initialStateAck
				} else {
					_ = try? await initialStateAck
				}
				await observability.endPhase("initial-state-handshake", success: true)
			} catch {
				await observability.endPhase("initial-state-handshake", success: false, error: error.localizedDescription)
				throw error
			}

			await observability.startPhase("publish-local-track")
			do {
				try await mediaChannel.publishLocalTracks(from: localStream)
				await observability.endPhase("publish-local-track", success: true)
			} catch {
				await observability.endPhase("publish-local-track", success: false, error: error.localizedDescription)
				throw error
			}

			suppressMediaConnectedState = false
			connectionState = .connected
			await observability.sessionStarted(roomInfo.sessionId)
			await observability.finishConnectionBreakdown(success: true)
			Task { [observability] in
				await observability.flushPendingIfNeeded()
			}
			return mediaChannel.currentRemoteStream
		} catch {
			await observability.finishConnectionBreakdown(success: false, error: error.localizedDescription)
			throw error
		}
	}

	func openSignalingPhase() async throws -> WebSocketClient {
		await observability.startPhase("websocket-open")
		do {
			let wsClient = try await WebSocketClient(
				url: signalingServerURL,
				timeout: options.connection.signalingConnectTimeout
			)
			await observability.endPhase("websocket-open", success: true)
			return wsClient
		} catch {
			await observability.endPhase("websocket-open", success: false, error: error.localizedDescription)
			throw error
		}
	}

	func joinRoomPhase(_ wsClient: WebSocketClient) async throws -> LiveKitRoomInfoMessage {
		await observability.startPhase("room-join")
		do {
			try await wsClient.send(OutgoingWebSocketMessage.liveKitJoin)
			let roomInfo = try await roomInfoRequest.wait(
				timeout: options.connection.roomInfoTimeout,
				timeoutError: DecartError.websocketError("LiveKit room info timed out")
			)
			await observability.endPhase("room-join", success: true)
			return roomInfo
		} catch {
			await observability.endPhase("room-join", success: false, error: error.localizedDescription)
			throw error
		}
	}

	func initialImageSizeKb() -> Int? {
		guard let data = options.initialPrompt.referenceImageData else { return nil }
		return Int((Double(data.count) / 1024).rounded())
	}

	func connectionLogMetadata(
		attempt: Int,
		isReconnectAttempt: Bool,
		phase: String? = nil,
		error: Error? = nil
	) -> [String: String] {
		var metadata = [
			"attempt": "\(attempt)",
			"isReconnectAttempt": "\(isReconnectAttempt)"
		]
		if let phase {
			metadata["phase"] = phase
		}
		if let error {
			metadata["error"] = error.localizedDescription
			metadata["errorType"] = String(describing: type(of: error))
		}
		return metadata
	}

	func closeRealtimeClients() async {
		await observability.stopNetworkMonitoring()
		await observability.setObservabilityForwarder(nil)
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

	func resetPendingRequests() async {
		roomInfoRequest.reset()
		await promptAckRequests.resetAll()
		setImageAckRequest.reset()
	}

	func failPendingRequests(_ error: Error) async {
		roomInfoRequest.fail(error)
		await promptAckRequests.failAll(error)
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
					await self.observability.emitInstrumentationEvent(
						"signaling-received",
						data: [
							"type": .string(roomInfo.type),
							"livekitUrl": .string(roomInfo.liveKitURL),
							"roomName": .string(roomInfo.roomName),
							"sessionId": .string(roomInfo.sessionId)
						]
					)
					self.roomInfoRequest.fulfill(roomInfo)
				case .promptAck(let ack):
					await self.promptAckRequests.fulfill(ack)
				case .setImageAck(let ack):
					self.setImageAckRequest.fulfill(ack)
				case .sessionId(let message):
					self.sessionId = message.id
					await self.observability.emitInstrumentationEvent(
						"signaling-received",
						data: ["type": .string(message.type)]
					)
				case .generationStarted:
					self.connectionState = .generating
					await self.observability.setConnectionDiagnosticsEnabled(false)
				case .generationTick(let tick):
					self.generationTick = tick.seconds
					await self.observability.setConnectionDiagnosticsEnabled(false)
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
					await self.failPendingRequests(error)
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
			await self?.failPendingRequests(disconnectError)
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
		let preferedCodec = lastPreferedCodec ?? .vp9

		isReconnecting = true
		connectionState = .reconnecting
		reconnectTask?.cancel()
		reconnectTask = Task { [weak self] in
			guard let self else { return }
			let startedAt = Date()
			let attemptNumber = self.reconnectAttempts + 1
			do {
				let newRemoteStream = try await self.connectWithRetry(
					localStream: localStream,
					preferedCodec: preferedCodec,
					isReconnectAttempt: true
				)
				self.remoteStreamContinuation.yield(newRemoteStream)
				self.reconnectAttempts = 0
				self.isReconnecting = false
				self.connectionState = .connected
				await self.observability.recordReconnect(
					attempt: attemptNumber,
					maxAttempts: self.maxReconnectAttempts,
					durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
					success: true
				)
			} catch {
				self.reconnectAttempts = self.maxReconnectAttempts
				self.isReconnecting = false
				self.connectionState = .error
				await self.observability.recordReconnect(
					attempt: attemptNumber,
					maxAttempts: self.maxReconnectAttempts,
					durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
					success: false,
					error: error.localizedDescription
				)
				await self.observability.flushPendingIfNeeded()
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

		let promptAckRequest = await promptAckRequests.prepare(prompt: prompt.text)
		let message: OutgoingWebSocketMessage = .prompt(PromptMessage(prompt: prompt.text, enhancePrompt: prompt.enrich))
		do {
			try await webSocketClient.send(message)
		} catch {
			await promptAckRequests.cancel(prompt: prompt.text, request: promptAckRequest, error: error)
			throw error
		}
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

// MARK: - Test hooks (@testable)

extension DecartRealtimeManager {
	internal func test_awaitRuntimePromptAck(prompt: String, timeout: TimeInterval) async throws {
		let request = await promptAckRequests.prepare(prompt: prompt)
		let ack = try await request.wait(
			timeout: timeout,
			timeoutError: DecartError.websocketError("Prompt acknowledgment timed out")
		)
		if ack.success != true {
			throw DecartError.serverError(ack.error ?? "Failed to send prompt")
		}
	}

	internal func test_recordPromptAck(_ ack: PromptAckMessage) async {
		await promptAckRequests.fulfill(ack)
	}

	internal func test_awaitRuntimeSetImageAck(timeout: TimeInterval) async throws {
		setImageAckRequest.reset(error: DecartError.serverError("superseded"))
		let ack = try await setImageAckRequest.wait(
			timeout: timeout,
			timeoutError: DecartError.websocketError("Image send timed out")
		)
		if ack.success != true {
			throw DecartError.serverError(ack.error ?? "Failed to set image")
		}
	}

	internal func test_recordSetImageAck(_ ack: SetImageAckMessage) {
		setImageAckRequest.fulfill(ack)
	}

	internal func test_failAllPendingRuntimeWaiters(_ error: Error) async {
		await promptAckRequests.failAll(error)
		setImageAckRequest.fail(error)
	}
}
