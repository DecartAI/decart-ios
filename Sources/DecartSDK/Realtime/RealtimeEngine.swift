import Foundation
import WebRTC

public enum DecartSdkEvent: Sendable {
    case stateChanged(DecartRealtimeConnectionState)
    case error(Error)
}

public struct RealtimeEngine {
    internal let webRTCService: WebRTCService
    private let signalingServerURL: URL
    public let options: RealtimeConfig

    private let eventContinuation: AsyncStream<DecartSdkEvent>.Continuation
    public let events: AsyncStream<DecartSdkEvent>

    public init(signalingServerURL: URL, options: RealtimeConfig) throws {
        self.options = options
        self.signalingServerURL = signalingServerURL

        let (stream, continuation) = AsyncStream.makeStream(
            of: DecartSdkEvent.self,
            bufferingPolicy: .bufferingNewest(4)
        )
        self.events = stream
        self.eventContinuation = continuation

        self.webRTCService = WebRTCService(
            realtimeConfig: options
        )

        Task {
            for await state in await webRTCService.signalingManager.events {
                continuation.yield(.stateChanged(state))
            }
        }
    }

    public func connect(localStream: RealtimeMediaStream) async throws -> RealtimeMediaStream {
        return try await connectWithRetry(
            localStream: localStream,
            maxRetries: 3,
            permanentErrors: ["permission denied", "not allowed", "invalid session"]
        )
    }

    public func disconnect() async {
        eventContinuation.yield(.stateChanged(.disconnected))
        eventContinuation.finish()
        await webRTCService.disconnect()
    }

    public func setPrompt(_ prompt: Prompt) {
        webRTCService.sendWebsocketMessage(.prompt(PromptMessage(prompt: prompt.text)))
    }

    // MARK: - Private Helpers

    private func connectWithRetry(
        localStream: RealtimeMediaStream,
        maxRetries: Int,
        permanentErrors: [String]
    ) async throws -> RealtimeMediaStream {
        var retries = 0
        var delay: TimeInterval = 1.0

        while retries < maxRetries {
            do {
                try await webRTCService.connect(url: signalingServerURL, localStream: localStream)

                guard
                    let remoteVideoTrack = getTransceivers().first(where: { $0.mediaType == .video }
                    )?.receiver.track as? RTCVideoTrack
                else {
                    throw DecartError.webRTCError("Remote video track not found after connection.")
                }

                let remoteAudioTrack =
                    getTransceivers().first(where: { $0.mediaType == .audio })?.receiver.track
                    as? RTCAudioTrack

                return RealtimeMediaStream(
                    videoTrack: remoteVideoTrack,
                    audioTrack: remoteAudioTrack,
                    id: .remoteStream
                )
            } catch {
                let errorMessage = error.localizedDescription.lowercased()
                if permanentErrors.contains(where: { errorMessage.contains($0) }) {
                    DecartLogger.log(
                        "[RealtimeEngine] Permanent error detected, aborting retries.",
                        level: .error)
                    throw error
                }

                retries += 1
                if retries >= maxRetries {
                    DecartLogger.log("[RealtimeEngine] Max retries reached.", level: .error)
                    throw error
                }

                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay = min(delay * 2, 10.0)
            }
        }

        throw DecartError.webRTCError("Connection failed after max retries.")
    }
}
