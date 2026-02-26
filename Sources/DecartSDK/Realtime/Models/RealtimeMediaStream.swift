@preconcurrency import WebRTC

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

	public let videoTrack: RTCVideoTrack
	public let audioTrack: RTCAudioTrack?
	public let id: String

	public init(
		videoTrack: RTCVideoTrack,
		audioTrack: RTCAudioTrack? = nil,
		id: StreamId
	) {
		self.videoTrack = videoTrack
		self.audioTrack = audioTrack
		self.id = id.id
	}
}
