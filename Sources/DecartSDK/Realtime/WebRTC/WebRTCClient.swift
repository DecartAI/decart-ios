import Foundation
@preconcurrency import WebRTC

final class WebRTCClient: @unchecked Sendable {
	private nonisolated(unsafe) static var sharedFactory: RTCPeerConnectionFactory?
	private static let factoryLock = NSLock()

	nonisolated(unsafe) let factory: RTCPeerConnectionFactory
	let peerConnection: RTCPeerConnection
	let connectionStateStream: AsyncStream<RTCPeerConnectionState>

	private let delegateHandler: WebRTCDelegateHandler
	private let signalingClient: SignalingClient
	private let connectionStateContinuation: AsyncStream<RTCPeerConnectionState>.Continuation

	nonisolated(unsafe) var videoTransceiver: RTCRtpTransceiver?
	nonisolated(unsafe) var audioTransceiver: RTCRtpTransceiver?

	private static func getOrCreateFactory() -> RTCPeerConnectionFactory {
		factoryLock.lock()
		defer { factoryLock.unlock() }

		if let factory = sharedFactory {
			return factory
		}

		RTCInitializeSSL()

		let factory = RTCPeerConnectionFactory(
			encoderFactory: RTCDefaultVideoEncoderFactory(),
			decoderFactory: RTCDefaultVideoDecoderFactory()
		)
		sharedFactory = factory
		return factory
	}

	init(
		config: RTCConfiguration,
		constraints: RTCMediaConstraints,
		videoConfig: RealtimeConfiguration.VideoConfig,
		sendMessage: @escaping (OutgoingWebSocketMessage) -> Void,
		withAudio: Bool
	) {
		self.factory = Self.getOrCreateFactory()

		let (stream, continuation) = AsyncStream.makeStream(of: RTCPeerConnectionState.self)
		self.connectionStateStream = stream
		self.connectionStateContinuation = continuation

		self.delegateHandler = WebRTCDelegateHandler(
			sendMessage: sendMessage,
			connectionStateContinuation: continuation
		)

		self.peerConnection = factory.peerConnection(
			with: config,
			constraints: constraints,
			delegate: delegateHandler
		)!

		self.signalingClient = SignalingClient(
			peerConnection: peerConnection,
			factory: factory,
			sendMessage: sendMessage
		)

		prepareTransceivers(videoConfig: videoConfig, withAudio: withAudio)
	}

	func handleSignalingMessage(_ message: IncomingWebSocketMessage) async throws {
		try await signalingClient.handleMessage(message)
	}

	deinit {
		DecartLogger.log("Webrtc client deinitialized", level: .info)
		close()
	}
}

// MARK: - Track Operations

extension WebRTCClient {
	func prepareTransceivers(videoConfig: RealtimeConfiguration.VideoConfig, withAudio: Bool) {
		if withAudio {
			let audioInit = RTCRtpTransceiverInit()
			audioInit.direction = .sendRecv
			audioTransceiver = peerConnection.addTransceiver(of: .audio, init: audioInit)
		}

		videoTransceiver = peerConnection.addTransceiver(of: .video, init: videoConfig.makeTransceiverInit())
		if let videoTransceiver {
			videoConfig.configureTransceiver(videoTransceiver, factory: factory)
		}
	}

	nonisolated func replaceVideoTrack(with newTrack: RTCVideoTrack) {
		guard let videoTransceiver else {
			fatalError("Video track does not exist")
		}
		videoTransceiver.sender.track = newTrack
	}

	nonisolated static func createVideoSource() -> RTCVideoSource {
		WebRTCClient.getOrCreateFactory().videoSource()
	}

	nonisolated static func createVideoTrack(source: RTCVideoSource, trackId: String) -> RTCVideoTrack {
		WebRTCClient.getOrCreateFactory().videoTrack(with: source, trackId: trackId)
	}

	nonisolated static func createAudioSource(constraints: RTCMediaConstraints? = nil) -> RTCAudioSource {
		WebRTCClient.getOrCreateFactory().audioSource(with: constraints)
	}

	nonisolated static func createAudioTrack(source: RTCAudioSource, trackId: String) -> RTCAudioTrack {
		WebRTCClient.getOrCreateFactory().audioTrack(with: source, trackId: trackId)
	}
}

// MARK: - Streaming

extension WebRTCClient {
	nonisolated func getRemoteRealtimeStream() -> RealtimeMediaStream? {
		guard let remoteVideoTrack = videoTransceiver?.receiver.track as? RTCVideoTrack else {
			return nil
		}

		let remoteAudioTrack = audioTransceiver?.receiver.track as? RTCAudioTrack

		return RealtimeMediaStream(
			videoTrack: remoteVideoTrack,
			audioTrack: remoteAudioTrack,
			id: .remoteStream
		)
	}

	@discardableResult
	nonisolated func startLocalStreaming(videoTrack: RTCVideoTrack, audioTrack: RTCAudioTrack? = nil) -> RealtimeMediaStream {
		if let videoSender = videoTransceiver?.sender {
			videoSender.track = videoTrack
		}

		if let audioSender = audioTransceiver?.sender {
			audioSender.track = audioTrack
		}

		return RealtimeMediaStream(
			videoTrack: videoTrack,
			audioTrack: audioTrack,
			id: .localStream
		)
	}
}

// MARK: - SDP Operations

extension WebRTCClient {
	func createOffer(constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
		guard let offer = try await peerConnection.offer(for: constraints) else {
			throw DecartError.webRTCError("failed to create offer")
		}
		return offer
	}

	func setLocalDescription(_ sdp: RTCSessionDescription) async throws {
		try await peerConnection.setLocalDescription(sdp)
	}
}

// MARK: - ICE Operations

extension WebRTCClient {
	func addIceCandidate(_ candidate: RTCIceCandidate) async throws {
		try await peerConnection.add(candidate)
	}
}

// MARK: - Cleanup

extension WebRTCClient {
	func close() {
		videoTransceiver?.sender.track = nil
		audioTransceiver?.sender.track = nil
		delegateHandler.cleanup()
		connectionStateContinuation.finish()
		peerConnection.close()
		peerConnection.delegate = nil
		videoTransceiver = nil
		audioTransceiver = nil
	}
}
