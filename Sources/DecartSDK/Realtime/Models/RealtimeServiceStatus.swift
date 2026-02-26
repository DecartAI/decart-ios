public enum RealtimeServiceStatus: String, Sendable {
	case unknown
	case enteringQueue = "Entering queue"
	case ready = "Ready"

	static func fromStatusString(_ status: String) -> RealtimeServiceStatus {
		let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		if normalized.contains("ready") {
			return .ready
		}
		if normalized.contains("entering queue") {
			return .enteringQueue
		}
		return .unknown
	}
}
