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
	#if os(iOS) || os(visionOS) || os(tvOS)
	private var previousAudioEngineAvailability: AudioEngineAvailability?
	private var previousAudioSessionAutomaticConfiguration: Bool?
	#endif

	init(
		videoPublishOptions: VideoPublishOptions,
		connectOptions: ConnectOptions,
		roomOptions: RoomOptions = RoomOptions(adaptiveStream: false, dynacast: false, reportRemoteTrackStatistics: true),
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
		restoreLiveKitAudioEngine()
		Task { await room?.disconnect() }
		remoteStreamContinuation.finish()
		connectionStateContinuation.finish()
		disconnectContinuation.finish()
		statsContinuation.finish()
	}

	func connect(roomInfo: LiveKitRoomInfoMessage) async throws {
		disableLiveKitAudioEngine()
		let room = Room(delegate: self, connectOptions: connectOptions, roomOptions: roomOptions)
		self.room = room
		remoteVideoTrack = nil
		statsPollingTask?.cancel()
		statsPollingTask = nil

		observability.emitLog(
			"LiveKit room connect starting",
			level: .info,
			category: "livekit.room",
			metadata: ["roomName": roomInfo.roomName]
		)

		do {
			try await room.connect(url: roomInfo.liveKitURL, token: roomInfo.token)
		} catch {
			restoreLiveKitAudioEngine()
			throw error
		}
		observability.emitLog(
			"LiveKit room connect completed",
			level: .info,
			category: "livekit.room",
			metadata: ["roomName": roomInfo.roomName]
		)
	}

	func disconnect() async {
		let room = room
		self.room = nil
		statsPollingTask?.cancel()
		statsPollingTask = nil
		localVideoTrack = nil
		remoteVideoTrack = nil
		await room?.disconnect()
		restoreLiveKitAudioEngine()
	}

	func publishLocalTracks(from stream: RealtimeMediaStream) async throws {
		guard let room else {
			throw DecartError.webRTCError("LiveKit room is not connected")
		}

		if let videoTrack = stream.videoTrack as? LocalVideoTrack {
			localVideoTrack = videoTrack
			await videoTrack.set(reportStatistics: true)
			startStatsPollingIfNeeded()
			observability.emitLog("publishing local video track", level: .debug, category: "livekit.publish")
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

	private func shouldAcceptTrack(from participant: RemoteParticipant) -> Bool {
		participant.identity?.stringValue.hasPrefix("inference-server-") == true
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
		let tracks: [Track] = [
			localVideoTrack,
			remoteVideoTrack
		].compactMap { $0 }

		for track in tracks {
			guard let statistics = track.statistics else { continue }
			statsContinuation.yield(DecartRealtimeWebRTCStats.make(from: statistics))
		}
	}

	private func disableLiveKitAudioEngine() {
		#if os(iOS) || os(visionOS) || os(tvOS)
		let audioManager = AudioManager.shared
		if previousAudioEngineAvailability == nil {
			previousAudioEngineAvailability = audioManager.engineAvailability
			previousAudioSessionAutomaticConfiguration = audioManager.audioSession.isAutomaticConfigurationEnabled
		}
		audioManager.audioSession.isAutomaticConfigurationEnabled = false
		do {
			try audioManager.setEngineAvailability(.none)
		} catch {
			observability.emitLog(
				"failed to disable LiveKit audio engine",
				level: .warning,
				category: "livekit.audio",
				metadata: ["error": error.localizedDescription]
			)
		}
		observability.emitLog("LiveKit audio engine disabled for video-only realtime session", level: .debug, category: "livekit.audio")
		#endif
	}

	private func restoreLiveKitAudioEngine() {
		#if os(iOS) || os(visionOS) || os(tvOS)
		let audioManager = AudioManager.shared
		if let previousAudioSessionAutomaticConfiguration {
			audioManager.audioSession.isAutomaticConfigurationEnabled = previousAudioSessionAutomaticConfiguration
		}
		if let previousAudioEngineAvailability {
			do {
				try audioManager.setEngineAvailability(previousAudioEngineAvailability)
			} catch {
				observability.emitLog(
					"failed to restore LiveKit audio engine",
					level: .warning,
					category: "livekit.audio",
					metadata: ["error": error.localizedDescription]
				)
			}
		}
		previousAudioSessionAutomaticConfiguration = nil
		previousAudioEngineAvailability = nil
		#endif
	}
}

extension LiveKitMediaChannel: RoomDelegate {
	func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) {
		observability.emitLog(
			"LiveKit room connection state update",
			level: .debug,
			category: "livekit.room",
			metadata: ["from": "\(oldConnectionState)", "to": "\(connectionState)"]
		)
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
		observability.emitLog(
			"LiveKit room disconnected",
			level: .warning,
			category: "livekit.room",
			metadata: ["error": error?.localizedDescription ?? "none"]
		)
		disconnectContinuation.yield(DisconnectInfo(reason: error?.localizedDescription))
	}

	func room(_ room: Room, didStartReconnectWithMode reconnectMode: ReconnectMode) {
		observability.emitLog(
			"LiveKit room reconnect starting",
			level: .warning,
			category: "livekit.room",
			metadata: ["mode": "\(reconnectMode)"]
		)
		connectionStateContinuation.yield(.reconnecting)
	}

	func room(_ room: Room, didCompleteReconnectWithMode reconnectMode: ReconnectMode) {
		observability.emitLog(
			"LiveKit room reconnect completed",
			level: .info,
			category: "livekit.room",
			metadata: ["mode": "\(reconnectMode)"]
		)
		connectionStateContinuation.yield(.connected)
	}

	func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
		guard shouldAcceptTrack(from: participant) else { return }
		switch publication.track {
		case let videoTrack as VideoTrack:
			remoteVideoTrack = videoTrack
			startStatsPollingIfNeeded()
			observability.emitLog(
				"remote video track received",
				level: .debug,
				category: "livekit.track",
				metadata: ["participant": participant.identity?.stringValue ?? ""]
			)
			emitRemoteStreamIfAvailable()
		default:
			break
		}
	}
}
