import Foundation

enum DecartUserAgent {
	static let sdkVersion = "0.0.0-dev"

	static func build(integration: String?) -> String {
		var parts = [
			"decart-swift-sdk/\(sdkVersion)",
			"lang/swift"
		]
		if let integration = integration?.trimmingCharacters(in: .whitespacesAndNewlines), !integration.isEmpty {
			parts.append("integration/\(integration)")
		}
		parts.append(runtime)
		return parts.joined(separator: " ")
	}

	private static var runtime: String {
		#if os(iOS)
			"runtime/ios"
		#elseif os(macOS)
			"runtime/macos"
		#elseif os(tvOS)
			"runtime/tvos"
		#elseif os(visionOS)
			"runtime/visionos"
		#else
			"runtime/apple"
		#endif
	}
}
