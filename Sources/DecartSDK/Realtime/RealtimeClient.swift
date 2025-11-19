import Foundation
import WebRTC

public final class RealtimeClient {
	let webRTCManager: WebRTCManager
	private let signalingServerURL: URL
	public let options: RealtimeConfiguration

	public let events: AsyncStream<DecartRealtimeConnectionState>

	public init(signalingServerURL: URL, options: RealtimeConfiguration) throws {
		self.options = options
		self.signalingServerURL = signalingServerURL

		self.webRTCManager = WebRTCManager(
			realtimeConfig: options
		)
		self.events = webRTCManager.signalingManager.events
	}

	public func connect(localStream: RealtimeMediaStream) async throws -> RealtimeMediaStream {
		webRTCManager.onWebrtcConnectedCallback = { [weak self] in
			guard let self = self else { return }
			self.setPrompt(self.options.initialState.prompt)
		}
		return try await connectWithRetry(
			localStream: localStream,
			maxRetries: 3,
			permanentErrors: ["permission denied", "not allowed", "invalid session"]
		)
	}

	public func disconnect() async {
		await webRTCManager.disconnect()
	}

	public func setPrompt(_ prompt: Prompt) {
		webRTCManager.sendWebsocketMessage(.prompt(PromptMessage(prompt: prompt.text)))
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
				try await webRTCManager.connect(url: signalingServerURL, localStream: localStream)

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
						"[RealtimeClient] Permanent error detected, aborting retries.",
						level: .error
					)
					throw error
				}

				retries += 1
				if retries >= maxRetries {
					DecartLogger.log("[RealtimeClient] Max retries reached.", level: .error)
					throw error
				}

				try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
				delay = min(delay * 2, 10.0)
			}
		}

		throw DecartError.webRTCError("Connection failed after max retries.")
	}
}
