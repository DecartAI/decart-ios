import Foundation

private struct InitialStateRequest: Sendable {
	let message: InitialStateMessage
	let ackTarget: InitialStateAckTarget
}

private enum InitialStateAckTarget: Sendable {
	case prompt(String)
	case setImage(failureMessage: String, timeoutMessage: String)
}

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

	private var liveKitMediaChannel: LiveKitMediaChannel?
	private var webSocketClient: WebSocketClient?

	private let signalingServerURL: URL
	private let stateContinuation: AsyncStream<DecartRealtimeState>.Continuation
	private let remoteStreamContinuation: AsyncStream<RealtimeMediaStream>.Continuation
	private var webSocketListenerTask: Task<Void, Never>?
	private var mediaListenerTask: Task<Void, Never>?
	private var mediaConnectionStateTask: Task<Void, Never>?
	private var mediaDisconnectTask: Task<Void, Never>?
	private var reconnectTask: Task<Void, Never>?
	private let initialStateAckTimeout: TimeInterval = 30
	private let promptAckTimeout: TimeInterval = 15
	private let imageAckTimeout: TimeInterval = 30
	private var isWaitingForInitialStateAck = false
	private var pendingLiveKitRoomInfo: LiveKitRoomInfoMessage?
	private var pendingPromptAcks: [PromptAckMessage] = []
	private var pendingSetImageAcks: [SetImageAckMessage] = []
	private var pendingInitialStateError: Error?

	// Serial queue around runtime ack waiters: CheckedContinuation forbids
	// double-resume, so ack delivery, timeout, and failure-propagation must
	// not race.
	private let ackQueue = DispatchQueue(label: "ai.decart.realtime.ack")
	// UUID-tagged waiters so a superseded call's send-task error handler can
	// detect it no longer owns the slot and avoid failing a newer waiter.
	private struct RuntimeWaiter {
		let id: UUID
		let cont: CheckedContinuation<Void, Error>
	}
	private var pendingRuntimePromptWaiters: [String: RuntimeWaiter] = [:]
	private var pendingRuntimeSetImageWaiter: RuntimeWaiter?
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
		failAllPendingRuntimeWaiters(DecartError.websocketError("WebSocket disconnected"))
		webSocketListenerTask?.cancel()
		mediaListenerTask?.cancel()
		mediaConnectionStateTask?.cancel()
		mediaDisconnectTask?.cancel()
		reconnectTask?.cancel()
		let liveKitMediaChannel = liveKitMediaChannel
		let webSocketClient = webSocketClient
		Task {
			await liveKitMediaChannel?.disconnect()
			await webSocketClient?.disconnect()
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
		failAllPendingRuntimeWaiters(DecartError.websocketError("WebSocket disconnected"))
		generationTick = nil
		sessionId = nil
		serviceStatus = .unknown
		queuePosition = nil
		queueSize = nil
		await closeRealtimeClients()
	}

	/// Updates the prompt and suspends until the server acks. Throws on ack
	/// failure, timeout, or websocket disconnect.
	///
	/// Reference-image models are single-flight: a pending call is failed
	/// with "superseded" before the new one is installed.
	func setPrompt(_ prompt: DecartPrompt) async throws {
		guard let webSocketClient else {
			throw DecartError.websocketError("WebSocket not connected")
		}

		if options.model.hasReferenceImage {
			let base64Image = prompt.referenceImageData?.base64EncodedString()
			let setImageMessage = SetImageMessage(
				imageData: base64Image,
				prompt: prompt.text,
				enhancePrompt: prompt.enrich
			)
			try await awaitRuntimeSetImageAck(timeout: imageAckTimeout) {
				try await webSocketClient.send(.setImage(setImageMessage) as OutgoingWebSocketMessage)
			}
		} else {
			let promptMessage = PromptMessage(prompt: prompt.text, enhancePrompt: prompt.enrich)
			try await awaitRuntimePromptAck(
				prompt: prompt.text,
				timeout: promptAckTimeout
			) {
				try await webSocketClient.send(.prompt(promptMessage) as OutgoingWebSocketMessage)
			}
		}
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

		let initialStateRequest = buildInitialStateRequest()
		try await sendMessageThrowing(.liveKitJoin(
			initialState: options.connection.bundleInitialStateInJoin ? initialStateRequest?.message : nil,
			encodesInitialState: options.connection.bundleInitialStateInJoin
		))
		let roomInfo = try await waitForLiveKitRoomInfo(timeout: options.connection.connectionTimeout)

		let mediaChannel = LiveKitMediaChannel(
			videoPublishOptions: options.media.video.publishOptions,
			connectOptions: options.connection.connectOptions
		)
		liveKitMediaChannel = mediaChannel
		setupMediaListeners(mediaChannel)

		let prearmedInitialStateAck = options.connection.bundleInitialStateInJoin && initialStateRequest != nil
		if prearmedInitialStateAck {
			isWaitingForInitialStateAck = true
		}
		defer {
			if prearmedInitialStateAck {
				isWaitingForInitialStateAck = false
				clearPendingInitialState()
			}
		}

		async let initialStateAck: Void = handleInitialStateAfterRoomInfo(initialStateRequest)
		try await mediaChannel.connect(roomInfo: roomInfo)
		try await initialStateAck
		try await mediaChannel.publishLocalTracks(from: localStream)
		return mediaChannel.currentRemoteStream
	}

	func closeRealtimeClients() async {
		// Cancelling the listener below skips its iterator-exit cleanup, so
		// fail runtime waiters here.
		failAllPendingRuntimeWaiters(DecartError.websocketError("WebSocket disconnected"))
		clearPendingInitialState()
		webSocketListenerTask?.cancel()
		webSocketListenerTask = nil
		mediaListenerTask?.cancel()
		mediaListenerTask = nil
		mediaConnectionStateTask?.cancel()
		mediaConnectionStateTask = nil
		mediaDisconnectTask?.cancel()
		mediaDisconnectTask = nil
		await liveKitMediaChannel?.disconnect()
		liveKitMediaChannel = nil
		await webSocketClient?.disconnect()
		webSocketClient = nil
		clearPendingInitialState()
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
					self.pendingLiveKitRoomInfo = roomInfo
					self.sessionId = roomInfo.sessionId
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
					self.failAllPendingRuntimeWaiters(error)
					self.connectionState = .error
				}
			}
			guard !Task.isCancelled else { return }
			let disconnectError = DecartError.websocketError("WebSocket disconnected")
			self?.recordInitialStateError(disconnectError)
			self?.failAllPendingRuntimeWaiters(disconnectError)
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
				DecartLogger.log("LiveKit room disconnected: \(disconnect.reason ?? "unknown")", level: .warning)
				self.connectionState = .disconnected
				self.handleUnexpectedDisconnect()
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

	func buildInitialStateRequest() -> InitialStateRequest? {
		let initialPrompt = options.initialPrompt
		if options.model.hasReferenceImage,
			let base64Image = initialPrompt.referenceImageData?.base64EncodedString()
		{
			let message = SetImageMessage(
				imageData: base64Image,
				prompt: initialPrompt.text,
				enhancePrompt: initialPrompt.enrich
			)
			return InitialStateRequest(
				message: .setImage(message),
				ackTarget: .setImage(
					failureMessage: "Failed to set initial image",
					timeoutMessage: "Initial image acknowledgment timed out"
				)
			)
		}

		guard !initialPrompt.text.isEmpty else { return nil }
		return InitialStateRequest(
			message: .prompt(PromptMessage(prompt: initialPrompt.text, enhancePrompt: initialPrompt.enrich)),
			ackTarget: .prompt(initialPrompt.text)
		)
	}

	func handleInitialStateAfterRoomInfo(_ request: InitialStateRequest?) async throws {
		if options.connection.bundleInitialStateInJoin {
			try await waitForBundledInitialStateAck(request)
		} else {
			try await sendInitialState()
		}
	}

	func waitForBundledInitialStateAck(_ request: InitialStateRequest?) async throws {
		guard let request else { return }

		isWaitingForInitialStateAck = true
		defer {
			isWaitingForInitialStateAck = false
			clearPendingInitialState()
		}

		switch request.ackTarget {
		case .prompt(let prompt):
			try await waitForPromptAck(prompt: prompt, timeout: initialStateAckTimeout)
		case .setImage(let failureMessage, let timeoutMessage):
			try await waitForSetImageAck(
				timeout: initialStateAckTimeout,
				failureMessage: failureMessage,
				timeoutMessage: timeoutMessage
			)
		}
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

	func waitForLiveKitRoomInfo(timeout: TimeInterval) async throws -> LiveKitRoomInfoMessage {
		let startTime = Date()
		while true {
			if let pendingLiveKitRoomInfo {
				self.pendingLiveKitRoomInfo = nil
				return pendingLiveKitRoomInfo
			}

			if connectionState == .disconnected {
				throw DecartError.websocketError("Disconnected while waiting for LiveKit room info")
			}

			if let error = pendingInitialStateError {
				connectionState = .error
				throw error
			}

			if Date().timeIntervalSince(startTime) > timeout {
				connectionState = .error
				throw DecartError.websocketError("LiveKit room info timed out")
			}

			try await Task.sleep(nanoseconds: 100_000_000)
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

			if let index = pendingPromptAcks.firstIndex(where: { $0.prompt == nil || $0.prompt == prompt }) {
				let ack = pendingPromptAcks.remove(at: index)
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

			if !pendingSetImageAcks.isEmpty {
				let ack = pendingSetImageAcks.removeFirst()
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

	// While the initial-state waiter is active it owns the next ack: a
	// concurrent runtime setPrompt must not steal it, or the connect path would
	// wait out its full timeout even though the server already responded. Acks
	// that land during connect/reconnect before that waiter starts are buffered
	// for it; runtime waiters only claim acks outside the active window.
	func recordPromptAck(_ ack: PromptAckMessage) {
		if isWaitingForInitialStateAck {
			pendingPromptAcks.append(ack)
			return
		}

		if resolveRuntimePromptAck(ack) {
			return
		}

		if shouldBufferInitialStateAck {
			pendingPromptAcks.append(ack)
		}
	}

	@discardableResult
	func resolveRuntimePromptAck(_ ack: PromptAckMessage) -> Bool {
		// Runtime path: match by exact prompt text only (same as JS/Python).
		var runtimeWaiter: RuntimeWaiter?
		if let promptText = ack.prompt {
			ackQueue.sync {
				runtimeWaiter = pendingRuntimePromptWaiters.removeValue(forKey: promptText)
			}
		}
		guard let waiter = runtimeWaiter else { return false }
		if ack.success == true {
			waiter.cont.resume()
		} else {
			waiter.cont.resume(throwing: DecartError.serverError(ack.error ?? "Failed to send prompt"))
		}
		return true
	}

	func recordSetImageAck(_ ack: SetImageAckMessage) {
		if isWaitingForInitialStateAck {
			pendingSetImageAcks.append(ack)
			return
		}

		if resolveRuntimeSetImageAck(ack) {
			return
		}

		if shouldBufferInitialStateAck {
			pendingSetImageAcks.append(ack)
		}
	}

	@discardableResult
	func resolveRuntimeSetImageAck(_ ack: SetImageAckMessage) -> Bool {
		var runtimeWaiter: RuntimeWaiter?
		ackQueue.sync {
			runtimeWaiter = pendingRuntimeSetImageWaiter
			pendingRuntimeSetImageWaiter = nil
		}
		guard let waiter = runtimeWaiter else { return false }
		if ack.success == true {
			waiter.cont.resume()
		} else {
			waiter.cont.resume(throwing: DecartError.serverError(ack.error ?? "Failed to set image"))
		}
		return true
	}

	func recordInitialStateError(_ error: Error) {
		guard isWaitingForInitialStateAck || shouldBufferInitialStateAck else { return }
		pendingInitialStateError = error
	}

	func failAllPendingRuntimeWaiters(_ error: Error) {
		var conts: [CheckedContinuation<Void, Error>] = []
		ackQueue.sync {
			conts.append(contentsOf: pendingRuntimePromptWaiters.values.map { $0.cont })
			pendingRuntimePromptWaiters.removeAll()
			if let setImage = pendingRuntimeSetImageWaiter {
				conts.append(setImage.cont)
				pendingRuntimeSetImageWaiter = nil
			}
		}
		for cont in conts {
			cont.resume(throwing: error)
		}
	}

	func clearPendingInitialState() {
		pendingPromptAcks.removeAll()
		pendingSetImageAcks.removeAll()
		pendingInitialStateError = nil
	}

	var shouldBufferInitialStateAck: Bool {
		connectionState == .connecting || connectionState == .reconnecting
	}

	// Install the waiter BEFORE invoking `send`, so a fast ack that arrives
	// while the send is still in flight is delivered to a registered waiter
	// instead of being dropped. The waiter's UUID is captured by the send
	// task's error handler so a stale (superseded) send can't fail a newer
	// waiter that happens to occupy the same key.
	func awaitRuntimePromptAck(
		prompt: String,
		timeout: TimeInterval,
		send: @escaping @Sendable () async throws -> Void
	) async throws {
		let id = UUID()
		let timeoutTask = Task { [weak self] in
			try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
			guard !Task.isCancelled, let self else { return }
			var waiterToFail: RuntimeWaiter?
			self.ackQueue.sync {
				if self.pendingRuntimePromptWaiters[prompt]?.id == id {
					waiterToFail = self.pendingRuntimePromptWaiters.removeValue(forKey: prompt)
				}
			}
			waiterToFail?.cont.resume(throwing: DecartError.websocketError("Prompt acknowledgment timed out"))
		}
		defer { timeoutTask.cancel() }

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			var priorWaiter: RuntimeWaiter?
			ackQueue.sync {
				priorWaiter = pendingRuntimePromptWaiters.removeValue(forKey: prompt)
				pendingRuntimePromptWaiters[prompt] = RuntimeWaiter(id: id, cont: continuation)
			}
			priorWaiter?.cont.resume(throwing: DecartError.serverError("superseded"))

			Task { [weak self] in
				do {
					try await send()
				} catch {
					var waiterToFail: RuntimeWaiter?
					self?.ackQueue.sync {
						if self?.pendingRuntimePromptWaiters[prompt]?.id == id {
							waiterToFail = self?.pendingRuntimePromptWaiters.removeValue(forKey: prompt)
						}
					}
					waiterToFail?.cont.resume(throwing: error)
				}
			}
		}
	}

	func awaitRuntimeSetImageAck(
		timeout: TimeInterval,
		send: @escaping @Sendable () async throws -> Void
	) async throws {
		let id = UUID()
		let timeoutTask = Task { [weak self] in
			try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
			guard !Task.isCancelled, let self else { return }
			var waiterToFail: RuntimeWaiter?
			self.ackQueue.sync {
				if self.pendingRuntimeSetImageWaiter?.id == id {
					waiterToFail = self.pendingRuntimeSetImageWaiter
					self.pendingRuntimeSetImageWaiter = nil
				}
			}
			waiterToFail?.cont.resume(throwing: DecartError.websocketError("Image send timed out"))
		}
		defer { timeoutTask.cancel() }

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			var priorWaiter: RuntimeWaiter?
			ackQueue.sync {
				priorWaiter = pendingRuntimeSetImageWaiter
				pendingRuntimeSetImageWaiter = RuntimeWaiter(id: id, cont: continuation)
			}
			priorWaiter?.cont.resume(throwing: DecartError.serverError("superseded"))

			Task { [weak self] in
				do {
					try await send()
				} catch {
					var waiterToFail: RuntimeWaiter?
					self?.ackQueue.sync {
						if self?.pendingRuntimeSetImageWaiter?.id == id {
							waiterToFail = self?.pendingRuntimeSetImageWaiter
							self?.pendingRuntimeSetImageWaiter = nil
						}
					}
					waiterToFail?.cont.resume(throwing: error)
				}
			}
		}
	}
}

// MARK: - Test hooks (@testable)

extension DecartRealtimeManager {
	internal func test_awaitRuntimePromptAck(prompt: String, timeout: TimeInterval) async throws {
		try await awaitRuntimePromptAck(prompt: prompt, timeout: timeout) { /* no-op send */ }
	}
	internal func test_awaitRuntimeSetImageAck(timeout: TimeInterval) async throws {
		try await awaitRuntimeSetImageAck(timeout: timeout) { /* no-op send */ }
	}
	internal func test_awaitInitialPromptAck(prompt: String, timeout: TimeInterval) async throws {
		isWaitingForInitialStateAck = true
		defer {
			isWaitingForInitialStateAck = false
			clearPendingInitialState()
		}
		try await waitForPromptAck(prompt: prompt, timeout: timeout)
	}
	internal func test_awaitInitialSetImageAck(timeout: TimeInterval) async throws {
		isWaitingForInitialStateAck = true
		defer {
			isWaitingForInitialStateAck = false
			clearPendingInitialState()
		}
		try await waitForSetImageAck(
			timeout: timeout,
			failureMessage: "Failed to set initial image",
			timeoutMessage: "Initial image acknowledgment timed out"
		)
	}
	internal func test_setConnectionState(_ state: DecartRealtimeConnectionState) {
		connectionState = state
	}
	internal var test_hasPendingInitialStateAck: Bool {
		!pendingPromptAcks.isEmpty || !pendingSetImageAcks.isEmpty || pendingInitialStateError != nil
	}
	internal func test_closeRealtimeClients() async {
		await closeRealtimeClients()
	}
	internal func test_recordPromptAck(_ ack: PromptAckMessage) { recordPromptAck(ack) }
	internal func test_recordSetImageAck(_ ack: SetImageAckMessage) { recordSetImageAck(ack) }
	internal func test_failAllPendingRuntimeWaiters(_ error: Error) {
		failAllPendingRuntimeWaiters(error)
	}
}
