import Foundation
@preconcurrency import WebRTC

public enum DecartSdkEvent: Sendable {
    case stateChanged(ConnectionState)
    case remoteStreamReceived(RTCMediaStream)
    case error(Error)
}

public struct PeerConnectionConfig {
    public let maxBitrate: Int
    public let minBitrate: Int
    public let maxFramerate: Int
    
    public init(maxBitrate: Int = 3800_000, minBitrate: Int = 800_000, maxFramerate: Int = 30) {
        self.maxBitrate = maxBitrate
        self.minBitrate = minBitrate
        self.maxFramerate = maxFramerate
    }
}

public struct RealtimeConnectOptions {
    public let model: ModelDefinition
    public let initialState: ModelState?
    public let peerConnectionConfig: PeerConnectionConfig
    public init(
        model: ModelDefinition,
        initialState: ModelState? = nil,
        peerConnectionConfig: PeerConnectionConfig = PeerConnectionConfig()
    ) {
        self.model = model
        self.initialState = initialState
        self.peerConnectionConfig = peerConnectionConfig
    }
}

public class RealtimeClient {
    private var webrtcConnection: WebRTCConnection?
    private let signalingServerURL: URL
    private let apiKey: String
    private let options: RealtimeConnectOptions
    
    private var eventContinuation: AsyncStream<DecartSdkEvent>.Continuation?
    public let events: AsyncStream<DecartSdkEvent>
    
    public init(baseURL: URL, apiKey: String, options: RealtimeConnectOptions) throws {
        self.options = options
        guard !apiKey.isEmpty else {
            print("[RealtimeClient] ❌ Error: API key is empty")
            throw DecartError.invalidAPIKey
        }

        self.apiKey = apiKey
        var baseURLString = baseURL.absoluteString
        if baseURLString.hasPrefix("https://") {
            baseURLString = baseURLString.replacingOccurrences(of: "https://", with: "wss://")
        } else if baseURLString.hasPrefix("http://") {
            baseURLString = baseURLString.replacingOccurrences(of: "http://", with: "ws://")
        }

        let urlString =
        "\(baseURLString)\(options.model.urlPath)?api_key=\(apiKey)&model=\(options.model.name)"

        guard let signalingServerURL = URL(string: urlString) else {
            print("[RealtimeClient] ❌ Error: Invalid base URL - \(urlString)")
            throw DecartError.invalidBaseURL(urlString)
        }

        self.signalingServerURL = signalingServerURL

        let (stream, continuation) = AsyncStream.makeStream(
            of: DecartSdkEvent.self,
            bufferingPolicy: .bufferingNewest(4)
        )
        self.events = stream
        self.eventContinuation = continuation
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
    
    public func connect(
        localStream: RTCMediaStream,
    ) async throws {
        // Create WebRTCConnection with callbacks
        let webrtcConnection = WebRTCConnection(
            onRemoteStream: { [weak self] stream in
                self?.sendRemoteStream(stream)
            },
            onStateChange: { [weak self] state in
                self?.sendConnectionState(state)
            },
            onError: { [weak self] error in
                print("[RealtimeClient] ❌ WebRTC error received: \(error.localizedDescription)")
                if let decartError = error as? DecartError {
                    self?.sendError(decartError)
                } else {
                    self?.sendError(.webRTCError(error))
                }
            },
            preferredVideoCodec: .vp8,
            peerConnectionConfig: options.peerConnectionConfig
        )
        
        self.webrtcConnection = webrtcConnection
        
        // Implement retry logic
        var retries = 0
        let maxRetries = 3
        var delay: TimeInterval = 1.0
        let permanentErrors = ["permission denied", "not allowed", "invalid session"]

        while retries < maxRetries {
            do {
                try await webrtcConnection.connect(url: signalingServerURL, localStream: localStream)
                return
            } catch {
                retries += 1

                let errorMessage = error.localizedDescription.lowercased()
                let isPermanentError = permanentErrors.contains { errorMessage.contains($0) }

                print("[RealtimeClient] ⚠️ Connection attempt \(retries) failed: \(error.localizedDescription)")

                if isPermanentError {
                    print("[RealtimeClient] ❌ Permanent error detected, aborting retries")
                    throw error
                }

                if retries >= maxRetries {
                    print("[RealtimeClient] ❌ Max retries reached, giving up")
                    throw error
                }

                await webrtcConnection.cleanup()
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay = min(delay * 2, 10.0)
            }
        }

        print("[RealtimeClient] ❌ Connection failed: Max retries exceeded")
        throw DecartError.webRTCError(
            NSError(domain: "WebRTC", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Max retries exceeded"]))
    }
    
    public func disconnect() async {
        guard let webrtcConnection = webrtcConnection else { return }
        await webrtcConnection.cleanup()
        self.webrtcConnection = nil
    }
    
    public func setPrompt(_ prompt: String, enrich: Bool = true) async throws {
        guard let webrtcConnection = webrtcConnection else {
            print("[RealtimeClient] ❌ Error: Cannot set prompt - client not initialized")
            throw DecartError.invalidOptions("Client not initialized")
        }
        guard !prompt.isEmpty else {
            print("[RealtimeClient] ❌ Error: Cannot set prompt - prompt is empty")
            throw DecartError.invalidInput("Prompt must not be empty")
        }

        await webrtcConnection.send(.prompt(PromptMessage(prompt: prompt)))
    }
    
    public func setMirror(_ enabled: Bool) async {
        guard let webrtcConnection = webrtcConnection else { return }

        let rotateY = enabled ? 2 : 0
        await webrtcConnection.send(.switchCamera(SwitchCameraMessage(rotateY: rotateY)))
    }
}
