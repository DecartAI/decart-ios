import Foundation
@preconcurrency import WebRTC

public enum DecartSdkEvent: Sendable {
    case stateChanged(ConnectionState)
    case remoteStreamReceived(RTCMediaStream)
    case error(Error)
}

public struct RealtimeConnectOptions {
    public let model: ModelDefinition
    public let initialState: ModelState?
    public let customizeOffer: ((RTCSessionDescription) async -> Void)?
    public let peerConnectionConfig: PeerConnectionConfig
    public init(
        model: ModelDefinition,
        initialState: ModelState? = nil,
        customizeOffer: ((RTCSessionDescription) async -> Void)? = nil,
        peerConnectionConfig: PeerConnectionConfig = PeerConnectionConfig()
    ) {
        self.model = model
        self.initialState = initialState
        self.customizeOffer = customizeOffer
        self.peerConnectionConfig = peerConnectionConfig
    }
}

public class RealtimeClient {
    private var webrtcManager: WebRTCManager?
    private var methods: RealtimeMethods?

    public let sessionId: UUID

    private var eventContinuation: AsyncStream<DecartSdkEvent>.Continuation?
    public let events: AsyncStream<DecartSdkEvent>

    init(
        webrtcManager: WebRTCManager?,
        sessionId: UUID
    ) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: DecartSdkEvent.self,
            bufferingPolicy: .bufferingNewest(4)
        )
        self.events = stream
        self.eventContinuation = continuation

        self.webrtcManager = webrtcManager
        self.sessionId = sessionId
        if let webrtcManager = webrtcManager {
            self.methods = RealtimeMethods(webrtcManager: webrtcManager)
        }
    }

    func setWebRTCManager(_ manager: WebRTCManager) {
        self.webrtcManager = manager
        self.methods = RealtimeMethods(webrtcManager: manager)
    }

    func sendConnectionState(_ state: ConnectionState) {
        eventContinuation?.yield(.stateChanged(state))
    }

    func sendError(_ error: DecartError) {
        eventContinuation?.yield(.error(error))
    }

    func sendRemoteStream(_ stream: RTCMediaStream) {
        eventContinuation?.yield(.remoteStreamReceived(stream))
    }

    public func enrichPrompt(_ prompt: String) async throws -> String {
        guard let methods = methods else {
            throw DecartError.invalidOptions("Client not initialized")
        }
        return try await methods.enrichPrompt(prompt)
    }

    public func setPrompt(_ prompt: String, enrich: Bool = true) async throws {
        guard let methods = methods else {
            throw DecartError.invalidOptions("Client not initialized")
        }
        try await methods.setPrompt(prompt, enrich: enrich)
    }

    public func setMirror(_ enabled: Bool) async {
        guard let methods = methods else { return }
        await methods.setMirror(enabled)
    }

    public func isConnected() -> Bool {
        guard let webrtcManager = webrtcManager else { return false }
        return webrtcManager.isConnected()
    }

    public func getConnectionState() -> ConnectionState {
        guard let webrtcManager = webrtcManager else { return .disconnected }
        return webrtcManager.getConnectionState()
    }

    public func disconnect() async {
        guard let webrtcManager = webrtcManager else { return }
        await webrtcManager.cleanup()
    }
}

public struct RealtimeClientFactory {
    private let baseURL: URL
    private let apiKey: String

    init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    public func connect(
        stream: RTCMediaStream,
        options: RealtimeConnectOptions
    ) async throws -> RealtimeClient {
        let sessionId = UUID()

        var baseURLString = baseURL.absoluteString
        if baseURLString.hasPrefix("https://") {
            baseURLString = baseURLString.replacingOccurrences(of: "https://", with: "wss://")
        } else if baseURLString.hasPrefix("http://") {
            baseURLString = baseURLString.replacingOccurrences(of: "http://", with: "ws://")
        }

        let urlString =
            "\(baseURLString)\(options.model.urlPath)?api_key=\(apiKey)&model=\(options.model.name)"

        guard let webrtcURL = URL(string: urlString) else {
            throw DecartError.invalidBaseURL(urlString)
        }

        let client = RealtimeClient(
            webrtcManager: nil,
            sessionId: sessionId
        )

        let config = WebRTCConfiguration(
            webrtcUrl: webrtcURL,
            apiKey: apiKey,
            sessionId: sessionId,
            fps: options.model.fps,
            onRemoteStream: { [weak client] stream in
                client?.sendRemoteStream(stream)
            },
            onConnectionStateChange: { [weak client] state in
                client?.sendConnectionState(state)
            },
            onError: { [weak client] error in
                if let decartError = error as? DecartError {
                    client?.sendError(decartError)
                } else {
                    client?.sendError(.webRTCError(error))
                }
            },
            initialState: options.initialState,
            customizeOffer: options.customizeOffer,
            preferredVideoCodec: .vp8,
            peerConnectionConfig: options.peerConnectionConfig
        )

        let webrtcManager = WebRTCManager(configuration: config)
        client.setWebRTCManager(webrtcManager)

        _ = try await webrtcManager.connect(localStream: stream)

        return client
    }
}
