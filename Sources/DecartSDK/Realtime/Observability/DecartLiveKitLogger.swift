import Foundation
@preconcurrency import LiveKit

enum DecartLiveKitLogging {
	static func install(observability: RealtimeObservability) {
		LiveKitSDK.setLogger(
			DecartLiveKitLogger(
				observability: observability,
				forwardedLogger: OSLogger(minLevel: .debug, rtc: true, ffi: true)
			)
		)
		observability.emitLog(
			"LiveKit logger installed with WebRTC and FFI forwarding",
			level: .debug,
			category: "livekit"
		)
	}
}

private final class DecartLiveKitLogger: LiveKit.Logger, @unchecked Sendable {
	private let observability: RealtimeObservability
	private let forwardedLogger: LiveKit.Logger

	init(observability: RealtimeObservability, forwardedLogger: LiveKit.Logger) {
		self.observability = observability
		self.forwardedLogger = forwardedLogger
	}

	func log(
		_ message: @autoclosure () -> CustomStringConvertible,
		_ level: LogLevel,
		source: @autoclosure () -> String?,
		file: StaticString,
		type: Any.Type,
		function: StaticString,
		line: UInt,
		metaData: ScopedMetadataContainer
	) {
		let resolvedMessage = message()
		let messageText = resolvedMessage.description.sanitizedLiveKitLogValue
		let decartLevel = level.decartLevel
		forwardedLogger.log(
			resolvedMessage,
			level,
			source: source(),
			file: file,
			type: type,
			function: function,
			line: line,
			metaData: metaData
		)

		let category = "livekit.\(String(describing: type))"
		let metadata = metaData.reduce(into: [String: String]()) { result, pair in
			result[pair.key] = pair.value.description.sanitizedLiveKitLogValue
		}
		observability.emitLog(
			messageText,
			level: decartLevel,
			category: category,
			metadata: metadata
		)
	}
}

private extension String {
	var sanitizedLiveKitLogValue: String {
		var result = self
		let patterns = [
			(#"(?i)(api_key|access_token|token)=([^&\s]+)"#, "$1=<redacted>"),
			(#"(?i)(authorization:\s*bearer\s+)[^\s,]+"#, "$1<redacted>"),
			(#"(?i)(bearer\s+)[^\s,]+"#, "$1<redacted>")
		]
		for (pattern, replacement) in patterns {
			result = result.replacingOccurrences(
				of: pattern,
				with: replacement,
				options: .regularExpression
			)
		}
		return result
	}
}

private extension LogLevel {
	var decartLevel: DecartRealtimeLogLevel {
		switch self {
		case .debug:
			return .debug
		case .info:
			return .info
		case .warning:
			return .warning
		case .error:
			return .error
		}
	}
}
