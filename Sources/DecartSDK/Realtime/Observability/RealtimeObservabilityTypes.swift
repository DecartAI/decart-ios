import Foundation
@preconcurrency import LiveKit

public enum DecartRealtimeJSONValue: Codable, Equatable, Sendable {
	case string(String)
	case int(Int)
	case double(Double)
	case bool(Bool)
	case object([String: DecartRealtimeJSONValue])
	case array([DecartRealtimeJSONValue])
	case null

	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if container.decodeNil() {
			self = .null
		} else if let value = try? container.decode(Bool.self) {
			self = .bool(value)
		} else if let value = try? container.decode(Int.self) {
			self = .int(value)
		} else if let value = try? container.decode(Double.self) {
			self = .double(value)
		} else if let value = try? container.decode(String.self) {
			self = .string(value)
		} else if let value = try? container.decode([String: DecartRealtimeJSONValue].self) {
			self = .object(value)
		} else if let value = try? container.decode([DecartRealtimeJSONValue].self) {
			self = .array(value)
		} else {
			throw DecodingError.dataCorruptedError(
				in: container,
				debugDescription: "Unsupported JSON value"
			)
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		switch self {
		case .string(let value):
			try container.encode(value)
		case .int(let value):
			try container.encode(value)
		case .double(let value):
			try container.encode(value)
		case .bool(let value):
			try container.encode(value)
		case .object(let value):
			try container.encode(value)
		case .array(let value):
			try container.encode(value)
		case .null:
			try container.encodeNil()
		}
	}
}

public enum DecartRealtimeLogLevel: String, Codable, Sendable {
	case debug
	case info
	case warning
	case error
}

public struct DecartRealtimeLogEvent: Codable, Sendable {
	public let timestamp: Int64
	public let level: DecartRealtimeLogLevel
	public let category: String
	public let message: String
	public let metadata: [String: String]

	public init(
		timestamp: Int64 = DecartRealtimeClock.nowMilliseconds(),
		level: DecartRealtimeLogLevel,
		category: String,
		message: String,
		metadata: [String: String] = [:]
	) {
		self.timestamp = timestamp
		self.level = level
		self.category = category
		self.message = message
		self.metadata = metadata
	}
}

public struct DecartRealtimeDiagnosticEvent: Codable, Sendable {
	public let name: String
	public let data: [String: DecartRealtimeJSONValue]
	public let timestamp: Int64

	public init(
		name: String,
		data: [String: DecartRealtimeJSONValue],
		timestamp: Int64 = DecartRealtimeClock.nowMilliseconds()
	) {
		self.name = name
		self.data = data
		self.timestamp = timestamp
	}
}

public struct DecartRealtimeWebRTCStats: Codable, Sendable {
	public struct Video: Codable, Sendable {
		public let framesDecoded: Int
		public let framesDropped: Int
		public let framesReceived: Int
		public let keyFramesDecoded: Int
		public let framesPerSecond: Double
		public let frameWidth: Int
		public let frameHeight: Int
		public let bytesReceived: UInt64
		public let packetsReceived: UInt64
		public let packetsLost: Int64
		public let jitter: Double
		public let bitrate: Double
		public let freezeCount: Int
		public let totalFreezesDuration: Double
		public let packetsLostDelta: Int64
		public let framesDroppedDelta: Int
		public let freezeCountDelta: Int
		public let freezeDurationDelta: Double
		public let nackCount: Int
		public let nackCountDelta: Int
		public let pliCount: Int
		public let firCount: Int
		public let avgDecodeTimeMs: Double?
		public let avgJitterBufferMs: Double?
		public let avgProcessingDelayMs: Double?
		public let avgInterFrameDelayMs: Double?
		public let interFrameDelayStdDevMs: Double?
		public let jitterBufferTargetDelayMs: Double?
		public let jitterBufferMinimumDelayMs: Double?
		public let decoderImplementation: String
	}

	public struct Audio: Codable, Sendable {
		public let bytesReceived: UInt64
		public let packetsReceived: UInt64
		public let packetsLost: Int64
		public let jitter: Double
		public let bitrate: Double
		public let packetsLostDelta: Int64
	}

	public struct OutboundVideo: Codable, Sendable {
		public let qualityLimitationReason: String
		public let qualityLimitationDurations: [String: Double]
		public let bytesSent: UInt64
		public let packetsSent: UInt64
		public let framesPerSecond: Double
		public let frameWidth: Int
		public let frameHeight: Int
		public let bitrate: Double
		public let targetBitrateKbps: Double?
		public let avgEncodeTimeMs: Double?
		public let avgPacketSendDelayMs: Double?
		public let avgQp: Double?
		public let nackCount: Int
		public let pliCount: Int
		public let firCount: Int
		public let retransmittedBytesSent: UInt64
		public let retransmittedPacketsSent: UInt64
		public let encoderImplementation: String
	}

	public struct RemoteInbound: Codable, Sendable {
		public let fractionLost: Double?
		public let jitter: Double?
		public let roundTripTime: Double?
	}

	public struct IceCandidateInfo: Codable, Sendable {
		public let candidateType: String
		public let address: String
		public let port: Int
		public let `protocol`: String
	}

	public struct IceCandidatePair: Codable, Sendable {
		public let local: IceCandidateInfo
		public let remote: IceCandidateInfo
	}

	public struct Connection: Codable, Sendable {
		public let currentRoundTripTime: Double?
		public let availableOutgoingBitrate: Double?
		public let selectedCandidatePairs: [IceCandidatePair]
	}

	public let timestamp: Int64
	public let video: Video?
	public let audio: Audio?
	public let outboundVideo: OutboundVideo?
	public let remoteInbound: RemoteInbound?
	public let connection: Connection
}

public enum DecartRealtimeClock {
	public static func nowMilliseconds() -> Int64 {
		Int64((Date().timeIntervalSince1970 * 1000).rounded())
	}
}

extension DecartRealtimeWebRTCStats {
	static func make(from statistics: TrackStatistics) -> DecartRealtimeWebRTCStats {
		let videoInbound = statistics.inboundRtpStream.first(where: { $0.kind == "video" || $0.framesDecoded != nil })
		let audioInbound = statistics.inboundRtpStream.first(where: { $0.kind == "audio" && $0.framesDecoded == nil })
		let outbound = statistics.outboundRtpStream.first(where: { $0.kind == "video" || $0.framesSent != nil })
		let remoteInbound = statistics.remoteInboundRtpStream.first
		let connection = connectionStats(from: statistics)

		return DecartRealtimeWebRTCStats(
			timestamp: DecartRealtimeClock.nowMilliseconds(),
			video: videoInbound.map(videoStats),
			audio: audioInbound.map(audioStats),
			outboundVideo: outbound.map(outboundVideoStats),
			remoteInbound: remoteInbound.map {
				RemoteInbound(
					fractionLost: $0.fractionLost,
					jitter: $0.jitter,
					roundTripTime: $0.roundTripTime
				)
			},
			connection: connection
		)
	}

	private static func videoStats(_ inbound: InboundRtpStreamStatistics) -> Video {
		let previous = inbound.previous
		let framesDropped = Int(inbound.framesDropped ?? 0)
		let freezeCount = Int(inbound.freezeCount ?? 0)
		let totalFreezesDuration = inbound.totalFreezesDuration ?? 0
		let nackCount = Int(inbound.nackCount ?? 0)
		return Video(
			framesDecoded: Int(inbound.framesDecoded ?? 0),
			framesDropped: framesDropped,
			framesReceived: Int(inbound.framesReceived ?? 0),
			keyFramesDecoded: Int(inbound.keyFramesDecoded ?? 0),
			framesPerSecond: inbound.framesPerSecond ?? 0,
			frameWidth: Int(inbound.frameWidth ?? 0),
			frameHeight: Int(inbound.frameHeight ?? 0),
			bytesReceived: inbound.bytesReceived ?? 0,
			packetsReceived: inbound.packetsReceived ?? 0,
			packetsLost: inbound.packetsLost ?? 0,
			jitter: inbound.jitter ?? 0,
			bitrate: bitrate(currentBytes: inbound.bytesReceived, previousBytes: previous?.bytesReceived, currentTimestamp: inbound.timestamp, previousTimestamp: previous?.timestamp),
			freezeCount: freezeCount,
			totalFreezesDuration: totalFreezesDuration,
			packetsLostDelta: (inbound.packetsLost ?? 0) - (previous?.packetsLost ?? 0),
			framesDroppedDelta: framesDropped - Int(previous?.framesDropped ?? 0),
			freezeCountDelta: freezeCount - Int(previous?.freezeCount ?? 0),
			freezeDurationDelta: totalFreezesDuration - (previous?.totalFreezesDuration ?? 0),
			nackCount: nackCount,
			nackCountDelta: nackCount - Int(previous?.nackCount ?? 0),
			pliCount: Int(inbound.pliCount ?? 0),
			firCount: Int(inbound.firCount ?? 0),
			avgDecodeTimeMs: averageMilliseconds(total: inbound.totalDecodeTime, count: inbound.framesDecoded),
			avgJitterBufferMs: averageMilliseconds(total: inbound.jitterBufferDelay, count: inbound.jitterBufferEmittedCount),
			avgProcessingDelayMs: averageMilliseconds(total: inbound.totalProcessingDelay, count: inbound.framesDecoded),
			avgInterFrameDelayMs: averageMilliseconds(total: inbound.totalInterFrameDelay, count: inbound.framesDecoded),
			interFrameDelayStdDevMs: interFrameStdDevMilliseconds(inbound),
			jitterBufferTargetDelayMs: inbound.jitterBufferTargetDelay.map { $0 * 1000 },
			jitterBufferMinimumDelayMs: inbound.jitterBufferMinimumDelay.map { $0 * 1000 },
			decoderImplementation: inbound.decoderImplementation ?? ""
		)
	}

	private static func audioStats(_ inbound: InboundRtpStreamStatistics) -> Audio {
		let previous = inbound.previous
		return Audio(
			bytesReceived: inbound.bytesReceived ?? 0,
			packetsReceived: inbound.packetsReceived ?? 0,
			packetsLost: inbound.packetsLost ?? 0,
			jitter: inbound.jitter ?? 0,
			bitrate: bitrate(currentBytes: inbound.bytesReceived, previousBytes: previous?.bytesReceived, currentTimestamp: inbound.timestamp, previousTimestamp: previous?.timestamp),
			packetsLostDelta: (inbound.packetsLost ?? 0) - (previous?.packetsLost ?? 0)
		)
	}

	private static func outboundVideoStats(_ outbound: OutboundRtpStreamStatistics) -> OutboundVideo {
		let previous = outbound.previous
		let framesEncoded = Double(outbound.framesEncoded ?? 0)
		let framesSent = Double(outbound.framesSent ?? 0)
		return OutboundVideo(
			qualityLimitationReason: outbound.qualityLimitationReason?.rawValue ?? "none",
			qualityLimitationDurations: [
				"none": outbound.qualityLimitationDurations?.none ?? 0,
				"cpu": outbound.qualityLimitationDurations?.cpu ?? 0,
				"bandwidth": outbound.qualityLimitationDurations?.bandwidth ?? 0,
				"other": outbound.qualityLimitationDurations?.other ?? 0
			],
			bytesSent: outbound.bytesSent ?? 0,
			packetsSent: outbound.packetsSent ?? 0,
			framesPerSecond: outbound.framesPerSecond ?? 0,
			frameWidth: Int(outbound.frameWidth ?? 0),
			frameHeight: Int(outbound.frameHeight ?? 0),
			bitrate: bitrate(currentBytes: outbound.bytesSent, previousBytes: previous?.bytesSent, currentTimestamp: outbound.timestamp, previousTimestamp: previous?.timestamp),
			targetBitrateKbps: outbound.targetBitrate.map { $0 / 1000 },
			avgEncodeTimeMs: framesEncoded > 0 ? ((outbound.totalEncodeTime ?? 0) / framesEncoded) * 1000 : nil,
			avgPacketSendDelayMs: framesSent > 0 ? ((outbound.totalPacketSendDelay ?? 0) / framesSent) * 1000 : nil,
			avgQp: framesEncoded > 0 ? Double(outbound.qpSum ?? 0) / framesEncoded : nil,
			nackCount: Int(outbound.nackCount ?? 0),
			pliCount: Int(outbound.pliCount ?? 0),
			firCount: Int(outbound.firCount ?? 0),
			retransmittedBytesSent: outbound.retransmittedBytesSent ?? 0,
			retransmittedPacketsSent: outbound.retransmittedPacketsSent ?? 0,
			encoderImplementation: outbound.encoderImplementation ?? ""
		)
	}

	private static func connectionStats(from statistics: TrackStatistics) -> Connection {
		let pairs = statistics.iceCandidatePair
			.filter { $0.state == .succeeded || $0.nominated == true }
			.compactMap { pair -> IceCandidatePair? in
				guard
					let localId = pair.localCandidateId,
					let remoteId = pair.remoteCandidateId,
					let local = statistics.localIceCandidate?.id == localId ? statistics.localIceCandidate : nil,
					let remote = statistics.remoteIceCandidate?.id == remoteId ? statistics.remoteIceCandidate : nil
				else { return nil }
				return IceCandidatePair(
					local: IceCandidateInfo(
						candidateType: local.candidateType?.rawValue ?? "",
						address: local.address ?? "",
						port: local.port ?? 0,
						protocol: local.protocol ?? ""
					),
					remote: IceCandidateInfo(
						candidateType: remote.candidateType?.rawValue ?? "",
						address: remote.address ?? "",
						port: remote.port ?? 0,
						protocol: remote.protocol ?? ""
					)
				)
			}

		let candidatePair = statistics.iceCandidatePair.first(where: { $0.state == .succeeded || $0.nominated == true })
		return Connection(
			currentRoundTripTime: candidatePair?.currentRoundTripTime,
			availableOutgoingBitrate: candidatePair?.availableOutgoingBitrate,
			selectedCandidatePairs: pairs
		)
	}

	private static func bitrate(
		currentBytes: UInt64?,
		previousBytes: UInt64?,
		currentTimestamp: Double,
		previousTimestamp: Double?
	) -> Double {
		guard
			let currentBytes,
			let previousBytes,
			let previousTimestamp,
			currentBytes >= previousBytes
		else { return 0 }
		let seconds = max((currentTimestamp - previousTimestamp) / 1_000_000, 0.001)
		return Double(currentBytes - previousBytes) * 8 / seconds
	}

	private static func averageMilliseconds(total: Double?, count: UInt?) -> Double? {
		guard let total, let count, count > 0 else { return nil }
		return (total / Double(count)) * 1000
	}

	private static func averageMilliseconds(total: Double?, count: UInt64?) -> Double? {
		guard let total, let count, count > 0 else { return nil }
		return (total / Double(count)) * 1000
	}

	private static func interFrameStdDevMilliseconds(_ inbound: InboundRtpStreamStatistics) -> Double? {
		guard
			let total = inbound.totalInterFrameDelay,
			let totalSquared = inbound.totalSquaredInterFrameDelay,
			let frames = inbound.framesDecoded,
			frames > 1
		else { return nil }
		let count = Double(frames)
		let mean = total / count
		let variance = max((totalSquared / count) - (mean * mean), 0)
		return sqrt(variance) * 1000
	}
}
