import Foundation
@preconcurrency import LiveKit

final class LiveKitMediaChannel: NSObject, @unchecked Sendable {
	struct DisconnectInfo: Sendable {
		let reason: String?
	}

	let remoteStreamUpdates: AsyncStream<RealtimeMediaStream>
	let connectionStateUpdates: AsyncStream<DecartRealtimeConnectionState>
	let disconnectUpdates: AsyncStream<DisconnectInfo>
	let statsUpdates: AsyncStream<DecartRealtimeWebRTCStats>

	private let videoPublishOptions: VideoPublishOptions
	private let connectOptions: ConnectOptions
	private let roomOptions: RoomOptions
	private let observability: RealtimeObservability
	private let remoteStreamContinuation: AsyncStream<RealtimeMediaStream>.Continuation
	private let connectionStateContinuation: AsyncStream<DecartRealtimeConnectionState>.Continuation
	private let disconnectContinuation: AsyncStream<DisconnectInfo>.Continuation
	private let statsContinuation: AsyncStream<DecartRealtimeWebRTCStats>.Continuation

	private var room: Room?
	private var remoteVideoTrack: VideoTrack?
	private var localVideoTrack: LocalVideoTrack?
	private var statsPollingTask: Task<Void, Never>?

	init(
		videoPublishOptions: VideoPublishOptions,
		connectOptions: ConnectOptions,
		roomOptions: RoomOptions = RoomOptions(adaptiveStream: false, dynacast: false),
		observability: RealtimeObservability
	) {
		self.videoPublishOptions = videoPublishOptions
		self.connectOptions = connectOptions
		self.roomOptions = roomOptions
		self.observability = observability

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

		let (statsUpdates, statsContinuation) = AsyncStream.makeStream(
			of: DecartRealtimeWebRTCStats.self,
			bufferingPolicy: .bufferingNewest(10)
		)
		self.statsUpdates = statsUpdates
		self.statsContinuation = statsContinuation
	}

	deinit {
		let room = room
		statsPollingTask?.cancel()
		Task { await room?.disconnect() }
		remoteStreamContinuation.finish()
		connectionStateContinuation.finish()
		disconnectContinuation.finish()
		statsContinuation.finish()
	}

	func connect(roomInfo: LiveKitRoomInfoMessage) async throws {
		let room = Room(delegate: self, connectOptions: connectOptions, roomOptions: roomOptions)
		self.room = room
		remoteVideoTrack = nil
		statsPollingTask?.cancel()
		statsPollingTask = nil

		try await room.connect(url: roomInfo.liveKitURL, token: roomInfo.token)
	}

	func disconnect() async {
		let room = room
		self.room = nil
		statsPollingTask?.cancel()
		statsPollingTask = nil
		localVideoTrack = nil
		remoteVideoTrack = nil
		await room?.disconnect()
	}

	func publishLocalTracks(from stream: RealtimeMediaStream) async throws {
		guard let room else {
			throw DecartError.webRTCError("LiveKit room is not connected")
		}

		if let videoTrack = stream.videoTrack as? LocalVideoTrack {
			localVideoTrack = videoTrack
			await videoTrack.set(reportStatistics: true)
			startStatsPollingIfNeeded()
			try await room.localParticipant.publish(videoTrack: videoTrack, options: videoPublishOptions)
		}
	}

	var currentRemoteStream: RealtimeMediaStream {
		RealtimeMediaStream(
			videoTrack: remoteVideoTrack,
			audioTrack: nil,
			id: .remoteStream
		)
	}

	private func emitRemoteStreamIfAvailable() {
		guard remoteVideoTrack != nil else { return }
		remoteStreamContinuation.yield(currentRemoteStream)
	}

	private func startStatsPollingIfNeeded() {
		guard statsPollingTask == nil else { return }
		statsPollingTask = Task { [weak self] in
			while !Task.isCancelled {
				self?.pollTrackState()
				try? await Task.sleep(nanoseconds: 1_000_000_000)
			}
		}
	}

	private func pollTrackState() {
		guard let statistics = localVideoTrack?.statistics else { return }
		statsContinuation.yield(DecartRealtimeWebRTCStats.make(from: statistics))
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
		observability.emitLog(
			"LiveKit reconnect started",
			level: .warning,
			category: "livekit.room",
			metadata: ["mode": "\(reconnectMode)"]
		)
		connectionStateContinuation.yield(.reconnecting)
	}

	func room(_ room: Room, didCompleteReconnectWithMode reconnectMode: ReconnectMode) {
		connectionStateContinuation.yield(.connected)
	}

	func room(_ room: Room, didFailToConnectWithError error: LiveKitError?) {
		observability.emitLog(
			"LiveKit room failed to connect",
			level: .error,
			category: "livekit.room",
			metadata: ["error": error?.localizedDescription ?? "unknown"]
		)
	}

	func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
		guard shouldAcceptTrack(from: participant) else { return }
		if let videoTrack = publication.track as? VideoTrack {
			remoteVideoTrack = videoTrack
			emitRemoteStreamIfAvailable()
		}
	}
}
