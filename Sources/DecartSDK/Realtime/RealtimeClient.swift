import Foundation
import WebRTC

public enum DecartSdkEvent: Sendable {
	case stateChanged(DecartRealtimeConnectionState)
	case error(Error)
}

// Technically you don't need MediaStreams anymore in unifiedPlan - which simplifies tracks control and disposal.
// this Wrapper is only ment to conform to the SDK's interface

public struct RealtimeClient {
	private let webRTCClient: WebRTCClient
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

		let webRTCClient = WebRTCClient(
			onStateChange: { state in
				continuation.yield(.stateChanged(state))
			},
			onError: { error in
				continuation.yield(.error(error))
			},
			realtimeConfig: options
		)

		self.webRTCClient = webRTCClient
	}

	public func connect(
		localStream: RealtimeMediaStream
	) async throws -> RealtimeMediaStream {
		// Implement retry logic
		var retries = 0
		let maxRetries = 3
		var delay: TimeInterval = 1.0
		let permanentErrors = ["permission denied", "not allowed", "invalid session"]

		while retries < maxRetries {
			do {
				try await webRTCClient
					.connect(url: signalingServerURL, localStream: localStream)
				let remoteVideoTrack = getTransceivers().first { $0.mediaType == .video }?.receiver.track as? RTCVideoTrack
				let remoteAudioTrack = getTransceivers().first {
					$0.mediaType == .audio
				}?.receiver.track as? RTCAudioTrack

				guard let remoteVideoTrack else {
					throw DecartError.webRTCError("please set local video track with RealtimeClient.setLocalVideoTrack before calling connect!")
				}
				return RealtimeMediaStream(
					videoTrack: remoteVideoTrack,
					audioTrack: remoteAudioTrack,
					id: .remoteStream
				)
			} catch {
				retries += 1

				let errorMessage = error.localizedDescription.lowercased()
				let isPermanentError = permanentErrors.contains { errorMessage.contains($0) }

				if isPermanentError {
					DecartLogger.log("[RealtimeClient] Permanent error detected, aborting retries", level: .error)
					throw error
				}

				if retries >= maxRetries {
					DecartLogger.log("[RealtimeClient] Max retries reached", level: .error)
					throw error
				}
				try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
				delay = min(delay * 2, 10.0)
			}
		}

		DecartLogger.log("max retries exceeded, connection failed", level: .error)
		throw DecartError.webRTCError("Max retries exceeded")
	}

	public func disconnect() async {
		eventContinuation.yield(.stateChanged(.disconnected))
		eventContinuation.finish()
		await webRTCClient.disconnect()
	}

	public func setPrompt(_ prompt: Prompt) async throws {
		await webRTCClient
			.sendWebsocketMessage(.prompt(PromptMessage(prompt: prompt.text)))
	}
}

public extension RealtimeClient {
	func createVideoSource() -> RTCVideoSource {
		return webRTCClient.factory.videoSource()
	}

	func createAudioSource(with: RTCMediaConstraints? = nil) -> RTCAudioSource {
		return webRTCClient.factory.audioSource(with: with)
	}

	/// Adding a video track or audio track implicitly creates a bidi Transceivers (per media type), RTCMediastream is not needed.
	func createLocalVideoTrack(with: RTCVideoSource, trackId: String, enabled: Bool = true) -> RTCVideoTrack {
		if !enabled {
			return webRTCClient.factory.videoTrack(with: with, trackId: trackId)
		}
		let videoTrack = webRTCClient.factory.videoTrack(with: with, trackId: trackId)
		videoTrack.isEnabled = true
		return videoTrack
	}

	func createLocalAudioTrack(with: RTCAudioSource, trackId: String, enabled: Bool = true) -> RTCAudioTrack {
		if !enabled {
			return webRTCClient.factory.audioTrack(with: with, trackId: trackId)
		}
		let audioTrack = webRTCClient.factory.audioTrack(with: with, trackId: trackId)
		audioTrack.isEnabled = true
		return audioTrack
	}

	func setTrackEnabled<T: RTCMediaStreamTrack>(_ type: T.Type, isEnabled: Bool) {
		webRTCClient.peerConnection.transceivers
			.compactMap { $0.sender.track as? T }
			.forEach { $0.isEnabled = isEnabled }
	}

	func getTransceivers() -> [RTCRtpTransceiver] {
		return webRTCClient.peerConnection.transceivers
	}
}
