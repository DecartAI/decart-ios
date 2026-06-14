@preconcurrency import LiveKit

public struct RealtimeMediaStream: Sendable {
	public enum StreamId {
		case localStream
		case remoteStream
		var id: String {
			switch self {
			case .localStream:
				return "stream-local"
			case .remoteStream:
				return "stream-remote"
			}
		}
	}

	public let videoTrack: VideoTrack?
	public let audioTrack: AudioTrack?
	public let id: String

	/// Glass-to-glass tracker, set by the SDK's `createLocalCameraStream(debugQuality:)`
	/// factory (and the deep-probe synthetic source) when measurement is on. The media
	/// channel wires the marker reader + snapshot to it. Nil for app-created streams.
	var seqTracker: SeqTracker?

	public init(
		videoTrack: VideoTrack? = nil,
		audioTrack: AudioTrack? = nil,
		id: StreamId
	) {
		self.videoTrack = videoTrack
		self.audioTrack = audioTrack
		self.id = id.id
	}
}
