public struct DecartRealtimeState: Sendable, Equatable {
	public let connectionState: DecartRealtimeConnectionState
	public let serviceStatus: RealtimeServiceStatus
	public let queuePosition: Int?
	public let queueSize: Int?

	public init(
		connectionState: DecartRealtimeConnectionState,
		serviceStatus: RealtimeServiceStatus,
		queuePosition: Int?,
		queueSize: Int?
	) {
		self.connectionState = connectionState
		self.serviceStatus = serviceStatus
		self.queuePosition = queuePosition
		self.queueSize = queueSize
	}
}
