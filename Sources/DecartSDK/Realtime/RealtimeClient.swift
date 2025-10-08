import Foundation
import Combine
import WebRTC

public struct RealtimeConnectOptions {
    public let model: ModelDefinition
    public let onRemoteStream: (RTCMediaStream) -> Void
    public let initialState: ModelState?
    public let customizeOffer: ((RTCSessionDescription) async -> Void)?
    
    public init(
        model: ModelDefinition,
        onRemoteStream: @escaping (RTCMediaStream) -> Void,
        initialState: ModelState? = nil,
        customizeOffer: ((RTCSessionDescription) async -> Void)? = nil
    ) {
        self.model = model
        self.onRemoteStream = onRemoteStream
        self.initialState = initialState
        self.customizeOffer = customizeOffer
    }
}

public actor RealtimeClient {
    private var webrtcManager: WebRTCManager?
    private var methods: RealtimeMethods?
    
    public let sessionId: UUID
    
    nonisolated private let _connectionStateSubject = PassthroughSubject<ConnectionState, Never>()
    nonisolated private let _errorSubject = PassthroughSubject<DecartError, Never>()
    
    public nonisolated var connectionStatePublisher: AnyPublisher<ConnectionState, Never> {
        _connectionStateSubject.eraseToAnyPublisher()
    }
    
    public nonisolated var errorPublisher: AnyPublisher<DecartError, Never> {
        _errorSubject.eraseToAnyPublisher()
    }
    
    init(
        webrtcManager: WebRTCManager?,
        sessionId: UUID
    ) {
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
    
    nonisolated func sendConnectionState(_ state: ConnectionState) {
        _connectionStateSubject.send(state)
    }
    
    nonisolated func sendError(_ error: DecartError) {
        _errorSubject.send(error)
    }
    
    public func enrichPrompt(_ prompt: String) async throws -> String {
        guard let methods = methods else { throw DecartError.invalidOptions("Client not initialized") }
        return try await methods.enrichPrompt(prompt)
    }
    
    public func setPrompt(_ prompt: String, enrich: Bool = true) async throws {
        guard let methods = methods else { throw DecartError.invalidOptions("Client not initialized") }
        try await methods.setPrompt(prompt, enrich: enrich)
    }
    
    public func setMirror(_ enabled: Bool) async {
        guard let methods = methods else { return }
        await methods.setMirror(enabled)
    }
    
    public func isConnected() async -> Bool {
        guard let webrtcManager = webrtcManager else { return false }
        return await webrtcManager.isConnected()
    }
    
    public func getConnectionState() async -> ConnectionState {
        guard let webrtcManager = webrtcManager else { return .disconnected }
        return await webrtcManager.getConnectionState()
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
        
        let urlString = "\(baseURLString)\(options.model.urlPath)?api_key=\(apiKey)&model=\(options.model.name)"
        
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
            onRemoteStream: options.onRemoteStream,
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
            customizeOffer: options.customizeOffer
        )
        
        let webrtcManager = WebRTCManager(configuration: config)
        await client.setWebRTCManager(webrtcManager)
        
        _ = try await webrtcManager.connect(localStream: stream)
        
        return client
    }
}
