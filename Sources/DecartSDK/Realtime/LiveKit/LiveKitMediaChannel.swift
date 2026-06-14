import Foundation
@preconcurrency import LiveKit

final class LiveKitMediaChannel: NSObject, @unchecked Sendable {
	struct DisconnectInfo: Sendable {
		let reason: String?
	}

	let remoteStreamUpdates: AsyncStream<RealtimeMediaStream>
	let connectionStateUpdates: AsyncStream<DecartRealtimeConnectionState>
	let disconnectUpdates: AsyncStream<DisconnectInfo>
	let connectionQualityUpdates: AsyncStream<ConnectionQualityReport>

	private let videoPublishOptions: VideoPublishOptions
	private let connectOptions: ConnectOptions
	private let roomOptions: RoomOptions
	private let remoteStreamContinuation: AsyncStream<RealtimeMediaStream>.Continuation
	private let connectionStateContinuation: AsyncStream<DecartRealtimeConnectionState>.Continuation
	private let disconnectContinuation: AsyncStream<DisconnectInfo>.Continuation
	/// Nil when connection-quality observability is disabled.
	private let connectionQualityCollector: ConnectionQualityStatsCollector?
	/// Glass-to-glass tracker (opt-in `debugQuality`); shared with the stamp pump
	/// (on the local track) and the marker reader (on the remote track). Nil when off.
	private let seqTracker: SeqTracker?
	private var markerReader: MarkerReader?

	private var room: Room?
	private var remoteVideoTrack: VideoTrack?
	private var remoteAudioTrack: AudioTrack?

	init(
		videoPublishOptions: VideoPublishOptions,
		connectOptions: ConnectOptions,
		roomOptions: RoomOptions = RoomOptions(adaptiveStream: false, dynacast: false),
		connectionQualityThresholds: ConnectionQualityThresholds? = nil,
		seqTracker: SeqTracker? = nil
	) {
		self.videoPublishOptions = videoPublishOptions
		self.connectOptions = connectOptions
		self.roomOptions = roomOptions
		self.seqTracker = seqTracker

		// Glass-to-glass implies the quality collector (it feeds measured latency in),
		// even if quality scoring wasn't separately enabled.
		let collectorThresholds = connectionQualityThresholds ?? (seqTracker != nil ? .default : nil)
		if let collectorThresholds {
			let collector = ConnectionQualityStatsCollector(thresholds: collectorThresholds, seqTracker: seqTracker)
			connectionQualityCollector = collector
			connectionQualityUpdates = collector.updates
		} else {
			connectionQualityCollector = nil
			// Disabled: an empty stream that yields nothing and finishes immediately.
			connectionQualityUpdates = AsyncStream { $0.finish() }
		}

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
		connectionQualityCollector?.stop()
		remoteStreamContinuation.finish()
		connectionStateContinuation.finish()
		disconnectContinuation.finish()
	}

	func connect(roomInfo: LiveKitRoomInfoMessage) async throws {
		let room = Room(delegate: self, connectOptions: connectOptions, roomOptions: roomOptions)
		self.room = room
		remoteVideoTrack = nil
		remoteAudioTrack = nil
		// Start the glass-to-glass TTFF clock for this attempt (resets the tracker).
		seqTracker?.markStart(monotonicMs())

		try await room.connect(url: roomInfo.liveKitURL, token: roomInfo.token)
	}

	func disconnect() async {
		let room = room
		self.room = nil
		if let markerReader, let remoteVideoTrack {
			remoteVideoTrack.remove(videoRenderer: markerReader)
		}
		markerReader = nil
		remoteVideoTrack = nil
		remoteAudioTrack = nil
		connectionQualityCollector?.stop()
		await room?.disconnect()
	}

	/// Latest interpreted connection-quality verdict, or nil before any stats arrive
	/// (or when observability is disabled).
	var currentConnectionQuality: ConnectionQualityReport? {
		connectionQualityCollector?.current()
	}

	/// Latest glass-to-glass snapshot (only under `debugQuality`), or nil.
	var currentGlassToGlass: G2GMetrics? {
		connectionQualityCollector?.currentGlassToGlass()
	}

	/// Whether the selected ICE path is TURN-relayed; nil until stats arrive.
	var isPathRelayed: Bool? {
		connectionQualityCollector?.currentIsRelayed()
	}

	func publishLocalTracks(from stream: RealtimeMediaStream) async throws {
		guard let room else {
			throw DecartError.webRTCError("LiveKit room is not connected")
		}

		if let videoTrack = stream.videoTrack as? LocalVideoTrack {
			try await room.localParticipant.publish(videoTrack: videoTrack, options: videoPublishOptions)
			await connectionQualityCollector?.attachLocal(videoTrack)
		}

		if let audioTrack = stream.audioTrack as? LocalAudioTrack {
			try await room.localParticipant.publish(audioTrack: audioTrack)
		}
	}

	var currentRemoteStream: RealtimeMediaStream {
		RealtimeMediaStream(
			videoTrack: remoteVideoTrack,
			audioTrack: remoteAudioTrack,
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
			if let collector = connectionQualityCollector {
				Task { await collector.attachRemote(videoTrack) }
			}
			// Glass-to-glass: read the marker off the rendered remote frames.
			if let seqTracker {
				let reader = MarkerReader(tracker: seqTracker)
				markerReader = reader
				videoTrack.add(videoRenderer: reader)
			}
			emitRemoteStreamIfAvailable()
		case let audioTrack as AudioTrack:
			remoteAudioTrack = audioTrack
			emitRemoteStreamIfAvailable()
		default:
			break
		}
	}
}
