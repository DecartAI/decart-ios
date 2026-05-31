import Foundation
@preconcurrency import LiveKit

/// Routes LiveKit's internal logs into SDK observability.
///
/// LiveKit freezes its shared logger on first use, so we install a single
/// process-wide logger and let it forward to whichever realtime session is
/// currently active. This is also the only way to obtain ICE / transport /
/// signaling detail during a connection that fails *before* any track is
/// published — at that point no `TrackStatistics` exist, but LiveKit still
/// logs peer-connection state changes, trickle ICE candidate activity, and
/// signaling transitions, which we capture here.
enum DecartLiveKitLogging {
	private static let shared = DecartLiveKitLogger(
		forwardedLogger: OSLogger(minLevel: .warning, rtc: false, ffi: false)
	)

	private static let installOnce: Void = {
		LiveKitSDK.setLogger(shared)
	}()

	/// Installs the SDK's LiveKit logger exactly once for the process. Must run
	/// before any LiveKit logging (LiveKit freezes the shared logger on first
	/// use); idempotent on subsequent calls.
	static func install() {
		_ = installOnce
	}

	/// The observability instance that LiveKit logs are routed to. Set when a
	/// session wires its observability forwarder, cleared on teardown.
	static func setActiveObservability(_ observability: RealtimeObservability?) {
		shared.setActiveObservability(observability)
	}

	/// While capturing, debug/info LiveKit logs (ICE/transport/signaling) are
	/// forwarded over the observability WebSocket. Warnings and errors are
	/// always forwarded regardless of this flag. Enabled only during the
	/// connection phase to bound steady-state volume.
	static func setCaptureVerbose(_ capturing: Bool) {
		shared.setCaptureVerbose(capturing)
	}
}

private final class DecartLiveKitLogger: LiveKit.Logger, @unchecked Sendable {
	private let forwardedLogger: LiveKit.Logger
	// Internal locking makes this @unchecked Sendable correct: all mutable
	// state is accessed only under `lock`.
	private let lock = NSLock()
	private var activeObservability: RealtimeObservability?
	private var captureVerbose = false
	private var lastForwardedSignature: String?

	init(forwardedLogger: LiveKit.Logger) {
		self.forwardedLogger = forwardedLogger
	}

	func setActiveObservability(_ observability: RealtimeObservability?) {
		lock.lock()
		activeObservability = observability
		lastForwardedSignature = nil
		lock.unlock()
	}

	func setCaptureVerbose(_ capturing: Bool) {
		lock.lock()
		captureVerbose = capturing
		lock.unlock()
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

		let decartLevel = level.decartLevel
		let isWarningOrError = decartLevel == .warning || decartLevel == .error

		lock.lock()
		let observability = activeObservability
		let shouldForward = observability != nil && (isWarningOrError || captureVerbose)
		lock.unlock()

		guard shouldForward, let observability else { return }

		let rawMessage = resolvedMessage.description
		// Warnings/errors always forward. For the verbose debug/info capture,
		// forward only allowlisted connection/ICE state-transition and failure
		// lines — everything else is dropped by default.
		if !isWarningOrError, !LiveKitLogNoiseFilter.isDiagnostic(rawMessage) { return }

		let messageText = rawMessage.sanitizedLiveKitLogValue
		let category = "livekit.\(String(describing: type))"

		// Drop identical consecutive lines to avoid duplicate spam.
		let signature = "\(category)|\(messageText)"
		lock.lock()
		let isDuplicate = signature == lastForwardedSignature
		lastForwardedSignature = signature
		lock.unlock()
		guard !isDuplicate else { return }

		let metadata = metaData.reduce(into: [String: String]()) { result, pair in
			result[pair.key] = pair.value.description.sanitizedLiveKitLogValue
		}
		Task {
			await observability.recordLiveKitConnectionLog(
				messageText,
				level: decartLevel,
				category: category,
				metadata: metadata
			)
		}
	}
}

/// Curated allowlist for LiveKit debug/info logs forwarded over the WS.
///
/// The server already logs routine LiveKit activity, so the client only adds
/// value by surfacing connection / ICE **state transitions** and **failures**.
/// Everything else (per-candidate trickle sends, SDP / data-channel /
/// negotiation chatter, server-info dumps, "waiting" lines, codec/permission
/// dumps, empty lines) is dropped by default. Warnings and errors bypass this
/// filter entirely (handled by the logger) so a real failure always surfaces.
enum LiveKitLogNoiseFilter {
	private static let diagnosticSignals = [
		"did update state",   // "Transport(subscriber) did update state: ..."
		"connectionstate:",   // "target: subscriber, connectionState: ..."
		"connection state",
		"icecandidate",       // "sending iceCandidate"
		"ice candidate",
		"ice restart",
		"reconnect",
		"disconnect",         // disconnected / disconnecting
		"fail",               // failed / failure / failures / failing
		"timeout",
		"timed out",
		"unable",
		"error"
	]

	/// Returns true only for debug/info lines worth forwarding: connection/ICE
	/// state transitions and failures. Routine chatter returns false.
	static func isDiagnostic(_ message: String) -> Bool {
		let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return false }
		let lowered = trimmed.lowercased()
		return diagnosticSignals.contains { lowered.contains($0) }
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
		case .debug: return .debug
		case .info: return .info
		case .warning: return .warning
		case .error: return .error
		}
	}
}
