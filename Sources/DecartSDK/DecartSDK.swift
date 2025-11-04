import Foundation

public struct DecartConfiguration {
	public let baseURL: URL
	public let apiKey: String

	public init(baseURL: URL, apiKey: String) {
		self.baseURL = baseURL
		self.apiKey = apiKey
	}

	public init(baseURL: String = "https://api3.decart.ai", apiKey: String) throws {
		guard let url = URL(string: baseURL) else {
			throw DecartError.invalidBaseURL(baseURL)
		}
		guard !apiKey.isEmpty else {
			throw DecartError.invalidAPIKey
		}
		self.baseURL = url
		self.apiKey = apiKey
	}
}

public struct DecartClient {
	public let baseURL: URL
	public let apiKey: String

	public init(configuration: DecartConfiguration) throws {
		guard !configuration.apiKey.isEmpty else {
			throw DecartError.invalidAPIKey
		}

		self.baseURL = configuration.baseURL
		self.apiKey = configuration.apiKey
	}

	public func createRealtimeClient(options: RealtimeConnectOptions) throws -> RealtimeClient {
		try RealtimeClient(baseURL: baseURL, apiKey: apiKey, options: options)
	}
}

public func createDecartClient(configuration: DecartConfiguration) throws -> DecartClient {
	try DecartClient(configuration: configuration)
}
