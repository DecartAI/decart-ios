import Foundation
@preconcurrency import WebRTC

final class WebRTCManager: NSObject {
	let factory: RTCPeerConnectionFactory

	@objc let peerConnection: RTCPeerConnection

	let signalingManager: SignalingManager
	private let realtimeConfig: RealtimeConfiguration
	var onWebrtcConnectedCallback: (() -> Void)?

	init(
		realtimeConfig: RealtimeConfiguration
	) {
		#if IS_DEVELOPMENT
			RTCSetMinDebugLogLevel(.verbose)
		#endif
		RTCInitializeSSL()
		let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
		let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
		self.factory = RTCPeerConnectionFactory(
			encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)

		let config = realtimeConfig.connection.makeRTCConfiguration()
		let constraints = realtimeConfig.media.connectionConstraints

		self.peerConnection = factory.peerConnection(
			with: config,
			constraints: constraints,
			delegate: nil)!
		self.signalingManager = SignalingManager(pc: peerConnection)
		self.realtimeConfig = realtimeConfig
		super.init()
		peerConnection.delegate = self
	}

	func connect(url: URL, localStream: RealtimeMediaStream, timeout: TimeInterval = 30)
		async throws
	{
		do {
			peerConnection.add(localStream.videoTrack, streamIds: [localStream.id])
			if let audioTrack = localStream.audioTrack {
				peerConnection.add(audioTrack, streamIds: [localStream.id])
			}

			if let transceiver = peerConnection.transceivers.first(where: { $0.mediaType == .video }
			) {
				await realtimeConfig.media.video.configure(
					transceiver: transceiver, factory: factory)
			}

			await signalingManager.connect(url: url)
			try await sendOffer()
		} catch {
			DecartLogger.log("failed to create webrtc connection", level: .error)
			await cleanup()
			throw error
		}
	}

	func disconnect() async {
		await cleanup()
	}

	func sendWebsocketMessage(_ message: OutgoingWebSocketMessage) {
		signalingManager.send(message)
	}

	private func cleanup() async {
		peerConnection.close()
		peerConnection.delegate = nil
		await signalingManager.disconnect()
	}

	private func handleConnectionStateChange(_ rtcState: RTCPeerConnectionState) {
		DecartLogger.log("got new state: \(rtcState)", level: .info)
		Task {
			await signalingManager.updatePeerConnectionState(rtcState)
		}
	}

	private func sendOffer() async throws {
		let constraints = realtimeConfig.media.offerConstraints
		guard let offer = try? await peerConnection.offer(for: constraints) else {
			throw DecartError.webRTCError("failed to create offer, aborting")
		}

		try await peerConnection.setLocalDescription(offer)
		signalingManager.send(.offer(OfferMessage(sdp: offer.sdp)))
	}

	deinit {
		DecartLogger.log("WebRTCManager deinit", level: .info)
	}
}

extension WebRTCManager: RTCPeerConnectionDelegate, @unchecked Sendable {
	func peerConnection(
		_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState
	) {}

	func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

	func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

	func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

	func peerConnection(
		_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState
	) {}

	func peerConnection(
		_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState
	) {}

	func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
		signalingManager.send(
			OutgoingWebSocketMessage.iceCandidate(
				.init(candidate: candidate)))
	}

	func peerConnection(
		_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]
	) {}

	func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

	func peerConnection(
		_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState
	) {
		if newState == .connected {
			onWebrtcConnectedCallback?()
		}

		handleConnectionStateChange(newState)
	}
}
