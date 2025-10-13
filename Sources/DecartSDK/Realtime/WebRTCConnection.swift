import Foundation
import WebRTC

public enum ConnectionState: Sendable {
    case connecting
    case connected
    case disconnected
}

class WebRTCConnection {
    private var peerConnection: RTCPeerConnection?
    private var signalingManager: SignalingManager?
    private var peerConnectionDelegate: PeerConnectionDelegate?
    private var factory: RTCPeerConnectionFactory?
    
    private(set) var state: ConnectionState = .disconnected
    
    private let onRemoteStream: ((RTCMediaStream) -> Void)?
    private let onStateChange: ((ConnectionState) -> Void)?
    private let onError: ((Error) -> Void)?
    private let preferredVideoCodec: VideoCodec?
    private let peerConnectionConfig: PeerConnectionConfig
    
    private static let iceServers: [RTCIceServer] = [
        RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
    ]
    
    init(
        onRemoteStream: ((RTCMediaStream) -> Void)? = nil,
        onStateChange: ((ConnectionState) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil,
        preferredVideoCodec: VideoCodec? = nil,
        peerConnectionConfig: PeerConnectionConfig
    ) {
        self.onRemoteStream = onRemoteStream
        self.onStateChange = onStateChange
        self.onError = onError
        self.preferredVideoCodec = preferredVideoCodec
        self.peerConnectionConfig = peerConnectionConfig
    }
    
    func connect(url: URL, localStream: RTCMediaStream, timeout: TimeInterval = 30) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        
        // Create and connect SignalingManager
        signalingManager = SignalingManager(onError: onError)
        
        do {
            try await signalingManager?.connect(url: url, timeout: timeout)
        } catch {
            print("[WebRTCConnection] Signaling connection failed: \(error.localizedDescription)")
            throw error
        }

        // Setup peer connection
        do {
            try await setupPeerConnection(localStream: localStream)
            subscribeToSignalingMessages()
            try await sendOffer()
        } catch {
            print("[WebRTCConnection] Peer connection setup failed: \(error.localizedDescription)")
            throw error
        }

        // Subscribe to signaling messages in background
        // Wait for connection
        while Date() < deadline {
            if state == .connected {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        print("[WebRTCConnection] Connection timeout after \(timeout)s")
        throw DecartError.connectionTimeout
    }
    
    private func subscribeToSignalingMessages() {
        guard let manager = signalingManager else { return }
        // Listen to all incoming messages
        Task { [weak self] in
            for await message in manager.messages {
                await self?.handleSignalingMessage(message)
            }
        }
    }
    
    private func setupPeerConnection(localStream: RTCMediaStream) async throws {
        peerConnection?.close()
        
        let config = RTCConfiguration()
        config.iceServers = Self.iceServers
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        
        let delegate = PeerConnectionDelegate(
            onRemoteStream: onRemoteStream,
            onIceCandidate: { [weak self] candidate in
                guard let sdpMid = candidate.sdpMid else { return }
                guard let self = self else { return }
                
                Task { [weak self] in
                    await self?.send(
                        .iceCandidate(
                            IceCandidateMessage(
                                candidate: candidate.sdp,
                                sdpMLineIndex: candidate.sdpMLineIndex,
                                sdpMid: sdpMid
                            )))
                }
            },
            onConnectionStateChange: { [weak self] rtcState in
                guard let self = self else { return }
                self.handleConnectionStateChange(rtcState)
            }
        )
        
        self.peerConnectionDelegate = delegate
        
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        peerConnection = self.factory?.peerConnection(
            with: config,
            constraints: constraints,
            delegate: delegate
        )
        
        for track in localStream.audioTracks {
            peerConnection?.add(track, streamIds: [localStream.streamId])
        }
        
        for track in localStream.videoTracks {
            peerConnection?.add(track, streamIds: [localStream.streamId])
        }
        
        if let pc = peerConnection, let codec = preferredVideoCodec {
            setCodecPreferences(for: pc, preferredCodec: codec)
        }
        
        configureSenderParameters(for: peerConnection)
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
        setState(newState)
    }
    
    private func sendOffer() async throws {
        guard let pc = peerConnection else {
            return
        }
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["OfferToReceiveVideo": "true"]
        )

        guard let offer = try await pc.offer(for: constraints) else {
            print("[WebRTCConnection] Failed to create offer")
            throw DecartError.webRTCError(
                NSError(
                    domain: "WebRTC", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create offer"]))
        }

        try await pc.setLocalDescription(offer)
        await send(.offer(OfferMessage(sdp: offer.sdp)))
    }
    
    private func handleSignalingMessage(_ message: IncomingWebSocketMessage) async {
        guard let pc = peerConnection else {
            return
        }

        do {
            switch message {
            case .offer(let msg):
                let sdp = RTCSessionDescription(type: .offer, sdp: msg.sdp)
                try await pc.setRemoteDescription(sdp)

                let constraints = RTCMediaConstraints(
                    mandatoryConstraints: nil,
                    optionalConstraints: nil
                )

                guard let answer = try await pc.answer(for: constraints) else {
                    print("[WebRTCConnection] Failed to create answer")
                    throw DecartError.webRTCError(
                        NSError(
                            domain: "WebRTC", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to create answer"]))
                }

                try await pc.setLocalDescription(answer)
                await send(.answer(AnswerMessage(type: "answer", sdp: answer.sdp)))

            case .answer(let msg):
                let sdp = RTCSessionDescription(type: .answer, sdp: msg.sdp)
                try await pc.setRemoteDescription(sdp)

            case .iceCandidate(let msg):
                let candidate = RTCIceCandidate(
                    sdp: msg.candidate.candidate,
                    sdpMLineIndex: msg.candidate.sdpMLineIndex,
                    sdpMid: msg.candidate.sdpMid
                )
                try await pc.add(candidate)
            }
        } catch {
            print("[WebRTCConnection] Signaling error: \(error.localizedDescription)")
            onError?(error)
        }
    }
    
    func send(_ message: OutgoingWebSocketMessage) async {
        await signalingManager?.send(message)
    }
    
    private func setState(_ newState: ConnectionState) {
        guard state != newState else { return }
        state = newState
        onStateChange?(newState)
    }
    
    func cleanup() async {
        peerConnection?.senders.forEach { sender in
            sender.track?.isEnabled = false
        }
        
        peerConnection?.close()
        peerConnection = nil
        
        await signalingManager?.disconnect()
        signalingManager = nil
        
        setState(.disconnected)
    }
    
    private func setCodecPreferences(
        for peerConnection: RTCPeerConnection, preferredCodec: VideoCodec
    ) {
        guard let transceiver = peerConnection.transceivers.first(where: { $0.mediaType == .video })
        else {
            return
        }

        guard let factory = self.factory else {
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
        transceiver.setCodecPreferences(sortedCodecs)
    }
    
    private func configureSenderParameters(for peerConnection: RTCPeerConnection?) {
        guard let pc = peerConnection,
              let sender = pc.senders.first(where: { $0.track?.kind == kRTCMediaStreamTrackKindVideo }
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
}

class PeerConnectionDelegate: NSObject, RTCPeerConnectionDelegate {
    private let onRemoteStream: ((RTCMediaStream) -> Void)?
    private let onIceCandidate: ((RTCIceCandidate) -> Void)?
    private let onConnectionStateChange: ((RTCPeerConnectionState) -> Void)?
    
    init(
        onRemoteStream: ((RTCMediaStream) -> Void)?,
        onIceCandidate: ((RTCIceCandidate) -> Void)?,
        onConnectionStateChange: ((RTCPeerConnectionState) -> Void)?
    ) {
        self.onRemoteStream = onRemoteStream
        self.onIceCandidate = onIceCandidate
        self.onConnectionStateChange = onConnectionStateChange
    }
    
    func peerConnection(
        _ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState
    ) {
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        onRemoteStream?(stream)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
    }
    
    func peerConnection(
        _ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState
    ) {
    }
    
    func peerConnection(
        _ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState
    ) {
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate)
    {
        onIceCandidate?(candidate)
    }
    
    func peerConnection(
        _ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]
    ) {
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    }
    
    func peerConnection(
        _ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState
    ) {
        onConnectionStateChange?(newState)
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
