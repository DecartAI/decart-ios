import Foundation
@preconcurrency import WebRTC

final class WebRTCClient: NSObject {
	let factory: RTCPeerConnectionFactory

	@objc let peerConnection: RTCPeerConnection

	let signalingManager: SignalingManager
	private let realtimeConfig: RealtimeConfig

	private static let iceServers: [RTCIceServer] = [
		RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
	]

	init(
		realtimeConfig: RealtimeConfig
	) {
		// #if IS_DEVELOPMENT
//		RTCSetMinDebugLogLevel(.verbose)
		// #else
//		RTCSetMinDebugLogLevel(.verbose)
		// #endif
		RTCInitializeSSL()
		let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
		let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
		self.factory = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)

		let config = RTCConfiguration()
		config.iceServers = Self.iceServers
		config.sdpSemantics = .unifiedPlan

		config.continualGatheringPolicy = .gatherContinually
		config.iceConnectionReceivingTimeout = 1000
		config.iceBackupCandidatePairPingInterval = 2000

		let constraints = RTCMediaConstraints(
			mandatoryConstraints: nil,
			optionalConstraints: nil
		)

		self.peerConnection = factory.peerConnection(
			with: config,
			constraints: constraints,
			delegate: nil
		)!
		self.signalingManager = SignalingManager(pc: peerConnection)
		self.realtimeConfig = realtimeConfig
		super.init()
		peerConnection.delegate = self
	}

	func connect(url: URL, localStream: RealtimeMediaStream, timeout: TimeInterval = 30) async throws {
		do {
			peerConnection.add(localStream.videoTrack, streamIds: [localStream.id])
			if let audioTrack = localStream.audioTrack {
				peerConnection.add(audioTrack, streamIds: [localStream.id])
			}
			configureSenderParameters(preferredCodec: VideoCodec.vp8)

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
		// Keeping delegate for now to handle closure events if any, or we can set to nil.
		// Setting to nil is safer to stop receiving events.
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
		let constraints = RTCMediaConstraints(
			mandatoryConstraints: nil,
			optionalConstraints: ["OfferToReceiveVideo": "true"]
		)
		guard let offer = try? await peerConnection.offer(for: constraints) else {
			throw DecartError.webRTCError("failed to create offer, aborting")
		}

		try await peerConnection.setLocalDescription(offer)
		signalingManager.send(.offer(OfferMessage(sdp: offer.sdp)))
	}

	private func configureSenderParameters(
		preferredCodec: VideoCodec
	) {
		guard let transceiver = peerConnection.transceivers.first(where: { $0.mediaType == .video })
		else {
			return
		}

		let supportedCodecs = factory.rtpSenderCapabilities(forKind: "video").codecs

		var preferredCodecs: [RTCRtpCodecCapability] = []
		var otherCodecs: [RTCRtpCodecCapability] = []
		var utilityCodecs: [RTCRtpCodecCapability] = []

		let preferredCodecName =
			preferredCodec.rawValue.components(separatedBy: "/").last?.uppercased() ?? ""

		for codec in supportedCodecs {
			let codecNameUpper = codec.name.uppercased()
			if codecNameUpper == preferredCodecName {
				preferredCodecs.append(codec)
			} else if codecNameUpper == "RTX" || codecNameUpper == "RED"
				|| codecNameUpper == "ULPFEC"
			{
				utilityCodecs.append(codec)
			} else {
				otherCodecs.append(codec)
			}
		}

		let sortedCodecs = preferredCodecs + otherCodecs + utilityCodecs
		try? transceiver.setCodecPreferences(sortedCodecs, error: ())
		let sender = transceiver.sender
		let parameters = sender.parameters
		let encodingParam = parameters.encodings[0]

		encodingParam.maxBitrateBps = NSNumber(value: realtimeConfig.peerConnectionConfig.maxBitrate)
		encodingParam.minBitrateBps = NSNumber(value: realtimeConfig.peerConnectionConfig.minBitrate)
		encodingParam.maxFramerate = NSNumber(
			value: realtimeConfig.peerConnectionConfig.maxFramerate
		)
		// encodingParam.scaleResolutionDownBy = NSNumber(value: scaleResolutionDownBy)

		parameters.encodings[0] = encodingParam
		sender.parameters = parameters
	}

	deinit { DecartLogger.log("WebRTCConnection deinit", level: .info) }
}

extension WebRTCClient: RTCPeerConnectionDelegate, @unchecked Sendable {
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
		signalingManager.send(OutgoingWebSocketMessage.iceCandidate(
			.init(candidate: candidate)))
	}

	func peerConnection(
		_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]
	) {}

	func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

	func peerConnection(
		_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState
	) {
		handleConnectionStateChange(newState)
	}
}
