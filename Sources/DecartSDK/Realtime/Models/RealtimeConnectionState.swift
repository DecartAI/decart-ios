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
