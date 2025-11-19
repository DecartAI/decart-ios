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

	public init(baseURL: String = "https://api3.decart.ai", apiKey: String) {
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

public struct DecartClient {
	let decartConfiguration: DecartConfiguration

	public init(decartConfiguration: DecartConfiguration) {
		self.decartConfiguration = decartConfiguration
	}

	public func createRealtimeClient(options: RealtimeConfiguration) throws -> RealtimeClient {
		let urlString =
			"\(decartConfiguration.signalingServerUrl)\(options.model.urlPath)?api_key=\(decartConfiguration.apiKey)&model=\(options.model.name)"

		guard let signalingServerURL = URL(string: urlString) else {
			DecartLogger.log("Unable to generate signaling server URL from: \(urlString)", level: .error)
			throw DecartError.invalidBaseURL(urlString)
		}

		return try RealtimeClient(
			signalingServerURL: signalingServerURL,
			options: options
		)
	}
}
