import Foundation

public struct DecartConfiguration {
	public let baseURL: URL
	public let apiKey: String

	var headers: [String: String] { ["Authorization": "Bearer \(apiKey)"] }

	var signalingServerUrl: String {
		var baseURLString = baseURL.absoluteString
		if baseURLString.hasPrefix("https://") {
			baseURLString = baseURLString.replacingOccurrences(of: "https://", with: "wss://")
		} else if baseURLString.hasPrefix("http://") {
			baseURLString = baseURLString.replacingOccurrences(of: "http://", with: "ws://")
		}
		return baseURLString
	}

	public init(baseURL: String = "https://api.decart.ai", apiKey: String) {
		guard let url = URL(string: baseURL) else {
			DecartLogger.log("Unable to create URL from: \(baseURL)", level: .error)
			fatalError("Unable to create URL from: \(baseURL)")
		}
		guard !apiKey.isEmpty else {
			DecartLogger.log("API key is empty", level: .error)
			fatalError("Api key is empty")
		}
		self.baseURL = url
		self.apiKey = apiKey
	}
}
