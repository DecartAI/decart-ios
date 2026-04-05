import Foundation

public struct ProcessClient: Sendable {
	private let session: URLSession
	private let request: URLRequest

	// MARK: - Initializers

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
		var files: [(String, FileInput)] = [("data", input.data)]
		if let ref = input.referenceImage { files.append(("reference_image", ref)) }
		try self.init(
			configuration: configuration,
			endpoint: modelDef.urlPath,
			params: [
				"prompt": input.prompt,
				"seed": input.seed,
				"resolution": input.resolution?.rawValue,
				"enhance_prompt": input.enhancePrompt,
			],
			files: files,
			session: session)
	}

	// MARK: - Private Common Init

	private init(
		configuration: DecartConfiguration,
		endpoint: String,
		params: [String: Any?],
		files: [(String, FileInput)],
		session: URLSession
	) throws {
		self.session = session
		let url = configuration.baseURL.appendingPathComponent(endpoint)
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-KEY")

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

		// Add files
		for (fieldName, fileInput) in files {
			body.append("--\(boundary)\r\n".data(using: .utf8)!)
			let filename = fileInput.filename.isEmpty ? "file" : fileInput.filename
			body.append(
				"Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n".data(
					using: .utf8)!)
			body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
			body.append(fileInput.data)
			body.append("\r\n".data(using: .utf8)!)
		}

		body.append("--\(boundary)--\r\n".data(using: .utf8)!)
		request.httpBody = body
		self.request = request
	}

	// MARK: - Process

	public nonisolated func process() async throws -> Data {
		let (data, response) = try await session.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw DecartError.networkError(URLError(.badServerResponse))
		}

		guard (200 ... 299).contains(httpResponse.statusCode) else {
			let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
			DecartLogger.log("error processing request: \(errorText), for route: \(request.url?.absoluteString ?? "unknown"), and body:", level: .error)
			throw DecartError.processingError(
				"Processing failed: \(httpResponse.statusCode) - \(errorText)")
		}

		return data
	}
}
