public struct DecartRealtimeState: Sendable, Equatable {
	public let connectionState: DecartRealtimeConnectionState
	public let serviceStatus: RealtimeServiceStatus
	public let queuePosition: Int?
	public let queueSize: Int?
	public let generationTick: Double?
	public let sessionId: String?

	public init(
		connectionState: DecartRealtimeConnectionState,
		serviceStatus: RealtimeServiceStatus,
		queuePosition: Int?,
		queueSize: Int?,
		generationTick: Double?,
		sessionId: String?
	) {
		self.connectionState = connectionState
		self.serviceStatus = serviceStatus
		self.queuePosition = queuePosition
		self.queueSize = queueSize
		self.generationTick = generationTick
		self.sessionId = sessionId
	}

	public static func == (lhs: DecartRealtimeState, rhs: DecartRealtimeState) -> Bool {
		lhs.connectionState == rhs.connectionState &&
		lhs.serviceStatus == rhs.serviceStatus &&
		lhs.queuePosition == rhs.queuePosition &&
		lhs.queueSize == rhs.queueSize &&
		lhs.generationTick == rhs.generationTick &&
		lhs.sessionId == rhs.sessionId
	}
}
