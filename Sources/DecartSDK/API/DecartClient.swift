import Foundation

public struct DecartClient {
	let decartConfiguration: DecartConfiguration

	public init(decartConfiguration: DecartConfiguration) {
		self.decartConfiguration = decartConfiguration
	}

	public func createRealtimeManager(options: RealtimeConfiguration) throws -> DecartRealtimeManager {
		let urlString =
			"\(decartConfiguration.signalingServerUrl)\(options.model.urlPath)?api_key=\(decartConfiguration.apiKey)&model=\(options.model.name)"

		guard let signalingServerURL = URL(string: urlString) else {
			DecartLogger.log("Unable to generate signaling server URL from: \(urlString)", level: .error)
			throw DecartError.invalidBaseURL(urlString)
		}

		return DecartRealtimeManager(
			signalingServerURL: signalingServerURL,
			options: options
		)
	}

	public func createProcessClient(
		model: VideoModel,
		input: TextToVideoInput,
		session: URLSession = .shared
	) throws -> ProcessClient {
		try ProcessClient(
			configuration: decartConfiguration,
			model: model,
			input: input,
			session: session
		)
	}

	public func createProcessClient(
		model: VideoModel,
		input: ImageToVideoInput,
		session: URLSession = .shared
	) throws -> ProcessClient {
		try ProcessClient(
			configuration: decartConfiguration,
			model: model,
			input: input,
			session: session
		)
	}

	public func createProcessClient(
		model: VideoModel,
		input: VideoToVideoInput,
		session: URLSession = .shared
	) throws -> ProcessClient {
		try ProcessClient(
			configuration: decartConfiguration,
			model: model,
			input: input,
			session: session
		)
	}

	public func createProcessClient(
		model: ImageModel,
		input: TextToImageInput,
		session: URLSession = .shared
	) throws -> ProcessClient {
		try ProcessClient(
			configuration: decartConfiguration,
			model: model,
			input: input,
			session: session
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
}
