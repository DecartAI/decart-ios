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
