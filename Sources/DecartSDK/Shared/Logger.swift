//
//  Logger.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 03/11/2025.
//
import Foundation

public enum DecartLogger: Sendable {
	public static let pringDebugLogs: Bool = ProcessInfo.processInfo.environment["ENABLE_DECART_SDK_DUBUG_LOGS"] == "YES"
	public enum Level: String, Sendable {
		case info = "ℹ️"
		case warning = "⚠️"
		case error = "❌"
		case success = "✅"
		case network = "🛜"
		case startedUpload = "↗️"
		case startedDownload = "⏬️"
		case audio = "🎷"
		case important = "⭐️"
	}

	static let dateFormatter: DateFormatter = {
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "MM/dd, h:mm:ss.SSS a zzz"
		return dateFormatter
	}()

	public static func log(_ string: String, level: Level, logBreadcrumbEnabled: Bool = true) {
		let logString = "[DecartSDK -\(dateFormatter.string(from: Date.now)) \(level.rawValue)] - \(string)"

		if !DecartLogger.pringDebugLogs {
			if level == .important || level == .error {
				print(logString)
			}
		} else {
			print(logString)
		}
	}
}
