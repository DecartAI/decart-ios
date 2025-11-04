//
//  Realtime.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 03/11/2025.
//
import WebRTC

public struct RealtimeMediaStream: Sendable {
	public enum StreamId {
		case localStream
		case remoteStream
		var id: String {
			switch self {
			case .localStream:
				return "stream-local"
			case .remoteStream:
				return "stream-remote" // It's good practice to handle all cases
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

public enum DecartRealtimeConnectionState: String, Sendable {
	case connecting = "Connecting"
	case connected = "Connected"
	case disconnected = "Disconnected"
	case idle = "Idle"
	case error = "Error"

	public var isConnected: Bool {
		self == .connected
	}

	public var isInSession: Bool {
		self == .connected || self == .connecting
	}
}
