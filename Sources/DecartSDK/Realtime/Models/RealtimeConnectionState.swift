public enum DecartRealtimeConnectionState: String, Sendable {
	case connecting = "Connecting"
	case connected = "Connected"
	case generating = "Generating"
	case reconnecting = "Reconnecting"
	case disconnected = "Disconnected"
	case idle = "Idle"
	case error = "Error"

	public var isConnected: Bool {
		self == .connected || self == .generating
	}

	public var isInSession: Bool {
		self == .connected || self == .connecting || self == .generating || self == .reconnecting
	}
}
