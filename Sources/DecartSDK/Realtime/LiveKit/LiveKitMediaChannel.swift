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
		// Realtime is video-only: configure LiveKit so it never touches the
		// microphone or the speaker before the room is created.
		Self.configureVideoOnlyAudio()

		let room = Room(delegate: self, connectOptions: connectOptions, roomOptions: roomOptions)
		self.room = room
		remoteVideoTrack = nil
		statsPollingTask?.cancel()
		statsPollingTask = nil

		// Connect failures are captured by the manager's connection-breakdown
		// diagnostic (the `webrtc-handshake` phase records the thrown error).
		do {
			try await room.connect(url: roomInfo.liveKitURL, token: roomInfo.token)
			if let snapshot = room.decartConnectSpanSnapshot() {
				await observability.recordLiveKitConnectSpan(snapshot)
			}
		} catch {
			if let snapshot = room.decartConnectSpanSnapshot() {
				await observability.recordLiveKitConnectSpan(snapshot)
			}
			throw error
		}
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

	/// Forces LiveKit into a video-only audio posture so a realtime session
	/// never requests microphone access (which would otherwise crash without
	/// `NSMicrophoneUsageDescription`) and never routes audio to the speaker.
	///
	/// - A playback-only `AVAudioSession` category guarantees the mic is never
	///   engaged, so no microphone usage description is required.
	/// - Disabling the audio engine entirely keeps both capture and playout off
	///   regardless of any track subscription.
	private static func configureVideoOnlyAudio() {
		#if os(iOS) || os(visionOS) || os(tvOS)
		AudioManager.shared.sessionConfiguration = .playback
		do {
			try AudioManager.shared.setEngineAvailability(.none)
		} catch {
			DecartLogger.log(
				"Failed to disable LiveKit audio engine: \(error.localizedDescription)",
				level: .warning
			)
		}
		#endif
	}

	func publishLocalTracks(from stream: RealtimeMediaStream) async throws {
		guard let room else {
			throw DecartError.webRTCError("LiveKit room is not connected")
		}

		// Video-only: the microphone is never captured or published.
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

	private func emitObservabilityEvent(
		_ name: String,
		data: [String: DecartRealtimeJSONValue] = [:]
	) {
		Task { [observability] in
			await observability.emitInstrumentationEvent(name, data: data)
		}
	}
}

private extension Room {
	func decartConnectSpanSnapshot(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> LiveKitConnectSpanSnapshot? {
		guard let span = connectSpan else { return nil }
		let entries = span.entries
		var previous = span.start
		let snapshotEntries = entries.map { entry in
			let elapsedMs = Int(max(entry.time - span.start, 0) * 1000)
			let deltaMs = Int(max(entry.time - previous, 0) * 1000)
			previous = entry.time
			return LiveKitConnectSpanSnapshot.Entry(
				label: entry.label,
				elapsedMs: elapsedMs,
				deltaMs: deltaMs
			)
		}
		let end = entries.last?.time ?? now
		return LiveKitConnectSpanSnapshot(
			totalDurationMs: Int(max(end - span.start, 0) * 1000),
			entries: snapshotEntries
		)
	}
}

extension LiveKitMediaChannel: RoomDelegate {
	// ConnectionStateChanged is intentionally not forwarded as an
	// observability event (it duplicates room-connected/-reconnecting/
	// -disconnected, matching the JS SDK), but it still drives the SDK
	// connection state machine.
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

	func roomDidConnect(_ room: Room) {
		emitObservabilityEvent(
			"room-connected",
			data: [
				"name": room.name.map { .string($0) } ?? .null,
				"sid": room.localParticipant.sid.map { .string($0.stringValue) } ?? .null
			]
		)
	}

	func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
		emitObservabilityEvent(
			"room-disconnected",
			data: [
				"reason": .null,
				"reasonName": error.map { .string($0.localizedDescription) } ?? .null
			]
		)
		disconnectContinuation.yield(DisconnectInfo(reason: error?.localizedDescription))
	}

	func room(_ room: Room, didStartReconnectWithMode reconnectMode: ReconnectMode) {
		emitObservabilityEvent("room-reconnecting")
		connectionStateContinuation.yield(.reconnecting)
	}

	func room(_ room: Room, didCompleteReconnectWithMode reconnectMode: ReconnectMode) {
		emitObservabilityEvent("room-reconnected")
		connectionStateContinuation.yield(.connected)
	}

	func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
		guard shouldAcceptTrack(from: participant) else { return }
		// Video-only: remote audio tracks are ignored so nothing is ever
		// routed to the speaker.
		if let videoTrack = publication.track as? VideoTrack {
			remoteVideoTrack = videoTrack
			emitRemoteStreamIfAvailable()
		}
	}
}
