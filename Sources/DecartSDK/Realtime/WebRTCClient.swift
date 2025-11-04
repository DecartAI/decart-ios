import Foundation
import WebRTC

public enum ConnectionState: Sendable {
	case connecting
	case connected
	case disconnected
}

class WebRTCClient: NSObject {
	private static let factory: RTCPeerConnectionFactory = {
		RTCInitializeSSL()
		let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
		let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
		return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
	}()

	@objc let peerConnection: RTCPeerConnection

	private(set) var state: ConnectionState = .disconnected
	private var signalingManager: SignalingManager?
	private let onRemoteStream: ((RTCMediaStream) -> Void)?
	private let onStateChange: ((ConnectionState) -> Void)?
	private let onError: ((Error) -> Void)?
	private let preferredVideoCodec: VideoCodec
	private let peerConnectionConfig: PeerConnectionConfig

	private static let iceServers: [RTCIceServer] = [
		RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
	]

	init(
		onRemoteStream: ((RTCMediaStream) -> Void)? = nil,
		onStateChange: ((ConnectionState) -> Void)? = nil,
		onError: ((Error) -> Void)? = nil,
		preferredVideoCodec: VideoCodec = VideoCodec.vp8,
		peerConnectionConfig: PeerConnectionConfig
	) {
		// #if IS_ALPHA
//		RTCSetMinDebugLogLevel(.verbose)
		// #else
//		RTCSetMinDebugLogLevel(.verbose)
		// #endif
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

		self.peerConnection = WebRTCClient.factory.peerConnection(
			with: config,
			constraints: constraints,
			delegate: nil
		)!
		self.onRemoteStream = onRemoteStream
		self.onStateChange = onStateChange
		self.onError = onError
		self.preferredVideoCodec = preferredVideoCodec
		self.peerConnectionConfig = peerConnectionConfig
		super.init()
		peerConnection.delegate = self
	}

	func connect(url: URL, localStream: RTCMediaStream, timeout: TimeInterval = 30) async throws {
		setState(.connecting)
		do {
			configureSenderParameters()
			for track in localStream.audioTracks {
				peerConnection.add(track, streamIds: [localStream.streamId])
			}

			for track in localStream.videoTracks {
				peerConnection.add(track, streamIds: [localStream.streamId])
			}

			let newSignalingManager = SignalingManager(pc: peerConnection)
			await newSignalingManager.connect(url: url)
			signalingManager = newSignalingManager
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

	func sendWebsocketMessage(_ message: OutgoingWebSocketMessage) async {
		await signalingManager?.send(message)
	}

	private func cleanup() async {
		peerConnection.close()
		peerConnection.delegate = nil
		await signalingManager?.disconnect()
		signalingManager = nil
		setState(.disconnected)
	}

	private func handleConnectionStateChange(_ rtcState: RTCPeerConnectionState) {
		let newState: ConnectionState
		switch rtcState {
		case .connected:
			newState = .connected
		case .connecting, .new:
			newState = .connecting
		default:
			newState = .disconnected
		}
		print("got new state: \(newState)")
		setState(newState)
	}

	private func sendOffer() async throws {
		let constraints = RTCMediaConstraints(
			mandatoryConstraints: nil,
			optionalConstraints: ["OfferToReceiveVideo": "true"]
		)
		guard let offer = try? await peerConnection.offer(for: constraints) else {
			throw DecartError.webRTCError(NSError(
				domain: "WebRTC", code: -1,
				userInfo: [NSLocalizedDescriptionKey: "Failed to create offer"]
			))
		}

		try await peerConnection.setLocalDescription(offer)
		await signalingManager?.send(.offer(OfferMessage(sdp: offer.sdp)))
	}

	private func setState(_ newState: ConnectionState) {
		guard state != newState else { return }
		state = newState
		onStateChange?(newState)
	}

	private func setCodecPreferences(
		for peerConnection: RTCPeerConnection, preferredCodec: VideoCodec
	) {
		guard let transceiver = peerConnection.transceivers.first(where: { $0.mediaType == .video })
		else {
			return
		}

		let supportedCodecs = WebRTCClient.factory.rtpSenderCapabilities(forKind: "video").codecs

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
//		var error: NSError?
		transceiver.setCodecPreferences(sortedCodecs)
	}

	private func configureSenderParameters() {
		guard let sender = peerConnection.senders.first(
			where: {
				$0.track?.kind == kRTCMediaStreamTrackKindVideo
			}
		),
			!sender.parameters.encodings.isEmpty
		else {
			return
		}

		let parameters = sender.parameters
		let encodingParam = parameters.encodings[0]

		encodingParam.maxBitrateBps = NSNumber(value: peerConnectionConfig.maxBitrate)
		encodingParam.minBitrateBps = NSNumber(value: peerConnectionConfig.minBitrate)
		encodingParam.maxFramerate = NSNumber(value: peerConnectionConfig.maxFramerate)
		// encodingParam.scaleResolutionDownBy = NSNumber(value: scaleResolutionDownBy)

		parameters.encodings[0] = encodingParam
		sender.parameters = parameters
	}

	deinit { DecartLogger.log("WebRTCConnection deinit", level: .info) }
}

extension WebRTCClient: RTCPeerConnectionDelegate {
	func peerConnection(
		_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState
	) {}

	func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
		onRemoteStream?(stream)
	}

	func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

	func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

	func peerConnection(
		_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState
	) {}

	func peerConnection(
		_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState
	) {}

	func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
		Task { [weak self] in
			guard let self else { return }
			await self.signalingManager?.send(OutgoingWebSocketMessage.iceCandidate(
				IceCandidateMessage(candidate: candidate)
			))
		}
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

extension RTCPeerConnection {
	func offer(for constraints: RTCMediaConstraints) async throws -> RTCSessionDescription? {
		try await withCheckedThrowingContinuation { continuation in
			self.offer(for: constraints) { sdp, error in
				if let error = error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume(returning: sdp)
				}
			}
		}
	}

	func answer(for constraints: RTCMediaConstraints) async throws -> RTCSessionDescription? {
		try await withCheckedThrowingContinuation { continuation in
			self.answer(for: constraints) { sdp, error in
				if let error = error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume(returning: sdp)
				}
			}
		}
	}

	func setLocalDescription(_ sdp: RTCSessionDescription) async throws {
		try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<Void, Error>) in
			self.setLocalDescription(sdp) { error in
				if let error = error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			}
		}
	}

	func setRemoteDescription(_ sdp: RTCSessionDescription) async throws {
		try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<Void, Error>) in
			self.setRemoteDescription(sdp) { error in
				if let error = error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			}
		}
	}

	func add(_ candidate: RTCIceCandidate) async throws {
		try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<Void, Error>) in
			self.add(candidate) { error in
				if let error = error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			}
		}
	}
}
