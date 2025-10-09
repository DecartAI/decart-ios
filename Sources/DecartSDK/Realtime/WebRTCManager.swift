import Foundation
import WebRTC

struct WebRTCConfiguration {
    let webrtcUrl: URL
    let apiKey: String
    let sessionId: UUID
    let fps: Int
    let onRemoteStream: (RTCMediaStream) -> Void
    let onConnectionStateChange: ((ConnectionState) -> Void)?
    let onError: ((Error) -> Void)?
    let initialState: ModelState?
    let customizeOffer: ((RTCSessionDescription) async -> Void)?
    let preferredVideoCodec: VideoCodec?
}

actor WebRTCManager {
    private var connection: WebRTCConnection
    private let configuration: WebRTCConfiguration
    
    private static let permanentErrors = [
        "permission denied",
        "not allowed",
        "invalid session"
    ]
    
    init(configuration: WebRTCConfiguration) {
        self.configuration = configuration
        self.connection = WebRTCConnection(
            onRemoteStream: configuration.onRemoteStream,
            onStateChange: configuration.onConnectionStateChange,
            onError: configuration.onError,
            customizeOffer: configuration.customizeOffer,
            preferredVideoCodec: configuration.preferredVideoCodec
        )
    }
    
    func connect(localStream: RTCMediaStream) async throws -> Bool {
        var retries = 0
        let maxRetries = 5
        var delay: TimeInterval = 1.0
        
        while retries < maxRetries {
            do {
                try await connection.connect(
                    url: configuration.webrtcUrl,
                    localStream: localStream
                )
                return true
            } catch {
                retries += 1
                
                let errorMessage = error.localizedDescription.lowercased()
                let isPermanentError = Self.permanentErrors.contains { errorMessage.contains($0) }
                
                if isPermanentError || retries >= maxRetries {
                    throw error
                }
                
                await connection.cleanup()
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                delay = min(delay * 2, 10.0)
            }
        }
        
        throw DecartError.webRTCError(NSError(domain: "WebRTC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retries exceeded"]))
    }
    
    func sendMessage(_ message: OutgoingWebRTCMessage) async {
        await connection.send(message)
    }
    
    func cleanup() async {
        await connection.cleanup()
    }
    
    func isConnected() async -> Bool {
        return await connection.state == .connected
    }
    
    func getConnectionState() async -> ConnectionState {
        return await connection.state
    }
}
