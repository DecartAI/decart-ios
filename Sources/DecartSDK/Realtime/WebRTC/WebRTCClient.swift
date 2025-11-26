import Foundation
@preconcurrency import WebRTC

final class WebRTCClient {
	let factory: RTCPeerConnectionFactory
	private(set) var peerConnection: RTCPeerConnection?
	private(set) var connectionStateStream: AsyncStream<RTCPeerConnectionState>?

	private var delegateHandler: WebRTCDelegateHandler?
	private var signalingClient: SignalingClient?
	private var connectionStateContinuation: AsyncStream<RTCPeerConnectionState>.Continuation?

	init() {
		#if IS_DEVELOPMENT
			RTCSetMinDebugLogLevel(.verbose)
		#endif
		RTCInitializeSSL()

		let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
		let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
		self.factory = RTCPeerConnectionFactory(
			encoderFactory: videoEncoderFactory,
			decoderFactory: videoDecoderFactory
		)
	}

	func createPeerConnection(
		config: RTCConfiguration,
		constraints: RTCMediaConstraints,
		sendMessage: @escaping (OutgoingWebSocketMessage) -> Void
	) {
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
			peerConnection: peerConnection!,
			factory: factory,
			sendMessage: sendMessage
		)
	}

	func handleSignalingMessage(_ message: IncomingWebSocketMessage) async throws {
		try await signalingClient?.handleMessage(message)
	}

	// MARK: - Track Operations

	func addTrack(_ track: RTCMediaStreamTrack, streamIds: [String]) {
		peerConnection?.add(track, streamIds: streamIds)
	}

	func configureVideoTransceiver(videoConfig: RealtimeConfiguration.VideoConfig) {
		if let transceiver = peerConnection?.transceivers.first(where: { $0.mediaType == .video }) {
			videoConfig.configure(transceiver: transceiver, factory: factory)
		}
	}

	var transceivers: [RTCRtpTransceiver] {
		peerConnection?.transceivers ?? []
	}

	// MARK: - SDP Operations

	func createOffer(constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
		guard let peerConnection else {
			throw DecartError.webRTCError("peer connection not initialized")
		}
		guard let offer = try await peerConnection.offer(for: constraints) else {
			throw DecartError.webRTCError("failed to create offer")
		}
		return offer
	}

	func createAnswer(constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
		guard let peerConnection else {
			throw DecartError.webRTCError("peer connection not initialized")
		}
		guard let answer = try await peerConnection.answer(for: constraints) else {
			throw DecartError.webRTCError("failed to create answer")
		}
		return answer
	}

	func setLocalDescription(_ sdp: RTCSessionDescription) async throws {
		guard let peerConnection else {
			throw DecartError.webRTCError("peer connection not initialized")
		}
		try await peerConnection.setLocalDescription(sdp)
	}

	func setRemoteDescription(_ sdp: RTCSessionDescription) async throws {
		guard let peerConnection else {
			throw DecartError.webRTCError("peer connection not initialized")
		}
		try await peerConnection.setRemoteDescription(sdp)
	}

	// MARK: - ICE Operations

	func addIceCandidate(_ candidate: RTCIceCandidate) async throws {
		guard let peerConnection else {
			throw DecartError.webRTCError("peer connection not initialized")
		}
		try await peerConnection.add(candidate)
	}

	// MARK: - Media Factory

	func createVideoSource() -> RTCVideoSource {
		factory.videoSource()
	}

	func createVideoTrack(source: RTCVideoSource, trackId: String) -> RTCVideoTrack {
		factory.videoTrack(with: source, trackId: trackId)
	}

	func createAudioSource(constraints: RTCMediaConstraints?) -> RTCAudioSource {
		factory.audioSource(with: constraints)
	}

	func createAudioTrack(source: RTCAudioSource, trackId: String) -> RTCAudioTrack {
		factory.audioTrack(with: source, trackId: trackId)
	}

	// MARK: - Cleanup

	func closePeerConnection() {
		delegateHandler?.cleanup()
		connectionStateContinuation?.finish()
		peerConnection?.close()
		peerConnection?.delegate = nil
		peerConnection = nil
		signalingClient = nil
		delegateHandler = nil
		connectionStateStream = nil
		connectionStateContinuation = nil
	}

	deinit {
		closePeerConnection()
	}
}
