import Foundation
@preconcurrency import LiveKit

final class LiveKitMediaChannel: NSObject, @unchecked Sendable {
	struct DisconnectInfo: Sendable {
		let reason: String?
	}

	let remoteStreamUpdates: AsyncStream<RealtimeMediaStream>
	let connectionStateUpdates: AsyncStream<DecartRealtimeConnectionState>
	let disconnectUpdates: AsyncStream<DisconnectInfo>

	private let videoPublishOptions: VideoPublishOptions
	private let connectOptions: ConnectOptions
	private let roomOptions: RoomOptions
	private let remoteStreamContinuation: AsyncStream<RealtimeMediaStream>.Continuation
	private let connectionStateContinuation: AsyncStream<DecartRealtimeConnectionState>.Continuation
	private let disconnectContinuation: AsyncStream<DisconnectInfo>.Continuation

	private var room: Room?
	private var remoteVideoTrack: VideoTrack?
	private var remoteAudioTrack: AudioTrack?

	init(
		videoPublishOptions: VideoPublishOptions,
		connectOptions: ConnectOptions,
		roomOptions: RoomOptions = RoomOptions(adaptiveStream: false, dynacast: false)
	) {
		self.videoPublishOptions = videoPublishOptions
		self.connectOptions = connectOptions
		self.roomOptions = roomOptions

		let (remoteStreamUpdates, remoteStreamContinuation) = AsyncStream.makeStream(
			of: RealtimeMediaStream.self,
			bufferingPolicy: .bufferingNewest(1)
		)
		self.remoteStreamUpdates = remoteStreamUpdates
		self.remoteStreamContinuation = remoteStreamContinuation

		let (connectionStateUpdates, connectionStateContinuation) = AsyncStream.makeStream(
			of: DecartRealtimeConnectionState.self,
			bufferingPolicy: .bufferingNewest(1)
		)
		self.connectionStateUpdates = connectionStateUpdates
		self.connectionStateContinuation = connectionStateContinuation

		let (disconnectUpdates, disconnectContinuation) = AsyncStream.makeStream(
			of: DisconnectInfo.self,
			bufferingPolicy: .bufferingNewest(1)
		)
		self.disconnectUpdates = disconnectUpdates
		self.disconnectContinuation = disconnectContinuation
	}

	deinit {
		let room = room
		Task { await room?.disconnect() }
		remoteStreamContinuation.finish()
		connectionStateContinuation.finish()
		disconnectContinuation.finish()
	}

	func connect(
		roomInfo: LiveKitRoomInfoMessage,
		localStream: RealtimeMediaStream,
		remoteTrackTimeout: TimeInterval
	) async throws -> RealtimeMediaStream {
		let room = Room(delegate: self, connectOptions: connectOptions, roomOptions: roomOptions)
		self.room = room
		remoteVideoTrack = nil
		remoteAudioTrack = nil

		try await room.connect(url: roomInfo.liveKitURL, token: roomInfo.token)
		try await publishLocalTracks(from: localStream, in: room)

		return try await waitForRemoteStream(timeout: remoteTrackTimeout)
	}

	func disconnect() async {
		let room = room
		self.room = nil
		remoteVideoTrack = nil
		remoteAudioTrack = nil
		await room?.disconnect()
	}

	private func publishLocalTracks(from stream: RealtimeMediaStream, in room: Room) async throws {
		if let videoTrack = stream.videoTrack as? LocalVideoTrack {
			try await room.localParticipant.publish(videoTrack: videoTrack, options: videoPublishOptions)
		}

		if let audioTrack = stream.audioTrack as? LocalAudioTrack {
			try await room.localParticipant.publish(audioTrack: audioTrack)
		}
	}

	private var currentRemoteStream: RealtimeMediaStream? {
		guard remoteVideoTrack != nil else { return nil }
		return RealtimeMediaStream(
			videoTrack: remoteVideoTrack,
			audioTrack: remoteAudioTrack,
			id: .remoteStream
		)
	}

	private func waitForRemoteStream(timeout: TimeInterval) async throws -> RealtimeMediaStream {
		let startTime = Date()
		while true {
			if let stream = currentRemoteStream {
				return stream
			}

			if Date().timeIntervalSince(startTime) > timeout {
				throw DecartError.webRTCError("LiveKit remote track subscription timed out")
			}

			try await Task.sleep(nanoseconds: 100_000_000)
		}
	}

	private func emitRemoteStreamIfAvailable() {
		guard let stream = currentRemoteStream else { return }
		remoteStreamContinuation.yield(stream)
	}

	private func shouldAcceptTrack(from participant: RemoteParticipant) -> Bool {
		participant.identity?.stringValue.hasPrefix("inference-server-") == true
	}
}

extension LiveKitMediaChannel: RoomDelegate {
	func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) {
		switch connectionState {
		case .connected:
			connectionStateContinuation.yield(.connected)
		case .connecting:
			connectionStateContinuation.yield(.connecting)
		case .reconnecting:
			connectionStateContinuation.yield(.reconnecting)
		case .disconnected:
			connectionStateContinuation.yield(.disconnected)
		default:
			break
		}
	}

	func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
		disconnectContinuation.yield(DisconnectInfo(reason: error?.localizedDescription))
	}

	func room(_ room: Room, didStartReconnectWithMode reconnectMode: ReconnectMode) {
		connectionStateContinuation.yield(.reconnecting)
	}

	func room(_ room: Room, didCompleteReconnectWithMode reconnectMode: ReconnectMode) {
		connectionStateContinuation.yield(.connected)
	}

	func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
		guard shouldAcceptTrack(from: participant) else { return }
		switch publication.track {
		case let videoTrack as VideoTrack:
			remoteVideoTrack = videoTrack
			emitRemoteStreamIfAvailable()
		case let audioTrack as AudioTrack:
			remoteAudioTrack = audioTrack
			emitRemoteStreamIfAvailable()
		default:
			break
		}
	}
}
