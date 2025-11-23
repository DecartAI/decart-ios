import Foundation

public struct ProcessClient {
	private let session: URLSession
	private let request: URLRequest

	// MARK: - Initializers

	/// Initializer for Text to Video models (e.g. lucy-pro-t2v)
	public init(
		configuration: DecartConfiguration,
		model: VideoModel,
		input: TextToVideoInput,
		session: URLSession = .shared
	) throws {
		guard ModelsInputFactory.videoInputType(for: model) == .textToVideo else {
			throw DecartError.invalidInput(
				"Model \(model.rawValue) does not support TextToVideoInput")
		}
		let modelDef = Models.video(model)
		try self.init(
			configuration: configuration,
			endpoint: modelDef.urlPath,
			params: [
				"prompt": input.prompt,
				"seed": input.seed,
				"resolution": input.resolution?.rawValue,
				"orientation": input.orientation,
			],
			file: nil,
			session: session
		)
	}

	/// Initializer for Text to Image models (e.g. lucy-pro-t2i)
	public init(
		configuration: DecartConfiguration,
		model: ImageModel,
		input: TextToImageInput,
		session: URLSession = .shared
	) throws {
		guard ModelsInputFactory.imageInputType(for: model) == .textToImage else {
			throw DecartError.invalidInput(
				"Model \(model.rawValue) does not support TextToImageInput")
		}
		let modelDef = Models.image(model)
		try self.init(
			configuration: configuration,
			endpoint: modelDef.urlPath,
			params: [
				"prompt": input.prompt,
				"seed": input.seed,
				"resolution": input.resolution?.rawValue,
				"orientation": input.orientation,
			],
			file: nil,
			session: session
		)
	}

	/// Initializer for Image to Video models (e.g. lucy-pro-i2v)
	public init(
		configuration: DecartConfiguration,
		model: VideoModel,
		input: ImageToVideoInput,
		session: URLSession = .shared
	) throws {
		guard ModelsInputFactory.videoInputType(for: model) == .imageToVideo else {
			throw DecartError.invalidInput(
				"Model \(model.rawValue) does not support ImageToVideoInput")
		}
		let modelDef = Models.video(model)
		try self.init(
			configuration: configuration,
			endpoint: modelDef.urlPath,
			params: [
				"prompt": input.prompt,
				"seed": input.seed,
				"resolution": input.resolution?.rawValue,
			],
			file: input.data,
			session: session
		)
	}

	/// Initializer for Image to Image models (e.g. lucy-pro-i2i)
	public init(
		configuration: DecartConfiguration,
		model: ImageModel,
		input: ImageToImageInput,
		session: URLSession = .shared
	) throws {
		guard ModelsInputFactory.imageInputType(for: model) == .imageToImage else {
			throw DecartError.invalidInput(
				"Model \(model.rawValue) does not support ImageToImageInput")
		}
		let modelDef = Models.image(model)
		try self.init(
			configuration: configuration,
			endpoint: modelDef.urlPath,
			params: [
				"prompt": input.prompt,
				"seed": input.seed,
				"resolution": input.resolution?.rawValue,
				"enhance_prompt": input.enhancePrompt,
			],
			file: input.data,
			session: session
		)
	}

	/// Initializer for Video to Video models (e.g. lucy-pro-v2v)
	public init(
		configuration: DecartConfiguration,
		model: VideoModel,
		input: VideoToVideoInput,
		session: URLSession = .shared
	) throws {
		guard ModelsInputFactory.videoInputType(for: model) == .videoToVideo else {
			throw DecartError.invalidInput(
				"Model \(model.rawValue) does not support VideoToVideoInput")
		}
		let modelDef = Models.video(model)
		try self.init(
			configuration: configuration,
			endpoint: modelDef.urlPath,
			params: [
				"prompt": input.prompt,
				"seed": input.seed,
				"resolution": input.resolution?.rawValue,
				"enhance_prompt": input.enhancePrompt,
				"num_inference_steps": input.numInferenceSteps,
			],
			file: input.data,
			session: session
		)
	}

	// MARK: - Private Common Init

	private init(
		configuration: DecartConfiguration,
		endpoint: String,
		params: [String: Any?],
		file: FileInput? = nil,
		session: URLSession
	) throws {
		self.session = session
		let url = configuration.baseURL.appendingPathComponent(endpoint)
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-KEY")
		// User-Agent logic could go here if needed

		let boundary = "Boundary-\(UUID().uuidString)"
		request.setValue(
			"multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

		var body = Data()

		// Add parameters
		for (key, value) in params {
			guard let value = value else { continue }
			body.append("--\(boundary)\r\n".data(using: .utf8)!)
			body.append(
				"Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
			body.append("\(value)\r\n".data(using: .utf8)!)
		}

		// Add file if present (always under the key "data")
		if let fileInput = file {
			body.append("--\(boundary)\r\n".data(using: .utf8)!)

			// Default filename and mime type logic
			let filename = fileInput.filename.isEmpty ? "file" : fileInput.filename
			// We could infer mime type from filename extension, defaulting to application/octet-stream
			let mimeType = "application/octet-stream"

			// The key for the file input is strictly "data" based on the single file constraint
			body.append(
				"Content-Disposition: form-data; name=\"data\"; filename=\"\(filename)\"\r\n".data(
					using: .utf8)!)
			body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)

			body.append(fileInput.data)
			body.append("\r\n".data(using: .utf8)!)
		}

		body.append("--\(boundary)--\r\n".data(using: .utf8)!)
		request.httpBody = body
		self.request = request
	}

	// MARK: - Process

	public func process() async throws -> Data {
		let (data, response) = try await session.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw DecartError.networkError(URLError(.badServerResponse))
		}

		guard (200...299).contains(httpResponse.statusCode) else {
			let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
			throw DecartError.processingError(
				"Processing failed: \(httpResponse.statusCode) - \(errorText)")
		}

		return data
	}
}
