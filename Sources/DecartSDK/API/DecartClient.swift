import Foundation

public struct DecartClient {
	let decartConfiguration: DecartConfiguration

	public init(decartConfiguration: DecartConfiguration) {
		self.decartConfiguration = decartConfiguration
	}

	public func createRealtimeManager(options: RealtimeConfiguration) throws -> DecartRealtimeManager {
		let urlString = "\(decartConfiguration.signalingServerUrl)\(options.model.urlPath)"
		guard var components = URLComponents(string: urlString) else {
			DecartLogger.log("Unable to generate signaling server URL from: \(urlString)", level: .error)
			throw DecartError.invalidBaseURL(urlString)
		}

		var queryItems = components.queryItems ?? []
		queryItems.append(URLQueryItem(name: "api_key", value: decartConfiguration.apiKey))
		queryItems.append(URLQueryItem(name: "model", value: options.model.name))
		queryItems.append(URLQueryItem(name: "user_agent", value: DecartUserAgent.build(integration: decartConfiguration.integration)))
		if let resolution = options.resolution {
			queryItems.append(URLQueryItem(name: "resolution", value: resolution.rawValue))
		}
		components.queryItems = queryItems

		guard let signalingServerURL = components.url else {
			DecartLogger.log("Unable to generate signaling server URL from: \(urlString)", level: .error)
			throw DecartError.invalidBaseURL(urlString)
		}

		return DecartRealtimeManager(
			signalingServerURL: signalingServerURL,
			options: options,
			apiKey: decartConfiguration.apiKey,
			integration: decartConfiguration.integration,
			telemetryEnabled: decartConfiguration.telemetryEnabled
		)
	}

	public func createProcessClient(
		model: ImageModel,
		input: ImageToImageInput,
		session: URLSession = .shared
	) throws -> ProcessClient {
		try ProcessClient(
			configuration: decartConfiguration,
			model: model,
			input: input,
			session: session
		)
	}

	public var queue: QueueClient {
		QueueClient(baseURL: decartConfiguration.baseURL, apiKey: decartConfiguration.apiKey)
	}
}
