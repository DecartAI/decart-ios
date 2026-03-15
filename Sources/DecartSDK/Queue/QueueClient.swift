import Foundation

public struct QueueClient: Sendable {
	private let session: URLSession
	private let baseURL: URL
	private let apiKey: String

	init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
		self.baseURL = baseURL
		self.apiKey = apiKey
		self.session = session
	}

	// MARK: - Submit

	public func submit(model: VideoModel, input: TextToVideoInput) async throws -> JobSubmitResponse {
		try await submitRequest(model: model, expectedType: .textToVideo, params: [
			"prompt": input.prompt,
			"seed": input.seed,
			"resolution": input.resolution?.rawValue,
			"orientation": input.orientation,
		], files: [])
	}

	public func submit(model: VideoModel, input: ImageToVideoInput) async throws -> JobSubmitResponse {
		try await submitRequest(model: model, expectedType: .imageToVideo, params: [
			"prompt": input.prompt,
			"seed": input.seed,
			"resolution": input.resolution?.rawValue,
		], files: [("data", input.data)])
	}

	public func submit(model: VideoModel, input: VideoToVideoInput) async throws -> JobSubmitResponse {
		try await submitRequest(model: model, expectedType: .videoToVideo, params: [
			"prompt": input.prompt,
			"seed": input.seed,
			"resolution": input.resolution?.rawValue,
			"enhance_prompt": input.enhancePrompt,
			"num_inference_steps": input.numInferenceSteps,
		], files: [("data", input.data)])
	}

	public func submit(model: VideoModel, input: VideoEditInput) async throws -> JobSubmitResponse {
		var files: [(String, FileInput)] = [("data", input.data)]
		if let ref = input.referenceImage { files.append(("reference_image", ref)) }
		return try await submitRequest(model: model, expectedType: .videoEdit, params: [
			"prompt": input.prompt,
			"seed": input.seed,
			"resolution": input.resolution?.rawValue,
			"enhance_prompt": input.enhancePrompt,
		], files: files)
	}

	public func submit(model: VideoModel, input: VideoRestyleInput) async throws -> JobSubmitResponse {
		var files: [(String, FileInput)] = [("data", input.data)]
		if let ref = input.referenceImage { files.append(("reference_image", ref)) }
		return try await submitRequest(model: model, expectedType: .videoRestyle, params: [
			"prompt": input.prompt,
			"seed": input.seed,
			"resolution": input.resolution?.rawValue,
			"enhance_prompt": input.enhancePrompt,
		], files: files)
	}

	public func submit(model: VideoModel, input: MotionVideoInput) async throws -> JobSubmitResponse {
		let trajectoryData = try JSONEncoder().encode(input.trajectory)
		guard let trajectoryString = String(data: trajectoryData, encoding: .utf8) else {
			throw DecartError.invalidInput("Unable to encode trajectory")
		}
		return try await submitRequest(model: model, expectedType: .motionVideo, params: [
			"trajectory": trajectoryString,
			"seed": input.seed,
			"resolution": input.resolution?.rawValue,
		], files: [("data", input.data)])
	}

	// MARK: - Status / Result

	public func status(jobId: String) async throws -> JobStatusResponse {
		let request = makeRequest(path: "/v1/jobs/\(jobId)", method: "GET")
		let (data, response) = try await session.data(for: request)
		try validateResponse(response, data: data, context: "status")
		return try decode(JobStatusResponse.self, from: data, context: "status")
	}

	public func result(jobId: String) async throws -> Data {
		let request = makeRequest(path: "/v1/jobs/\(jobId)/content", method: "GET")
		let (data, response) = try await session.data(for: request)
		try validateResponse(response, data: data, context: "result")
		return data
	}

	// MARK: - Convenience

	public func submitAndPoll(
		model: VideoModel,
		input: TextToVideoInput,
		onStatusChange: ((JobStatusResponse) -> Void)? = nil
	) async throws -> QueueJobResult {
		let response = try await submit(model: model, input: input)
		return try await poll(jobId: response.jobId, initialStatus: response.status, onStatusChange: onStatusChange)
	}

	public func submitAndPoll(
		model: VideoModel,
		input: ImageToVideoInput,
		onStatusChange: ((JobStatusResponse) -> Void)? = nil
	) async throws -> QueueJobResult {
		let response = try await submit(model: model, input: input)
		return try await poll(jobId: response.jobId, initialStatus: response.status, onStatusChange: onStatusChange)
	}

	public func submitAndPoll(
		model: VideoModel,
		input: VideoToVideoInput,
		onStatusChange: ((JobStatusResponse) -> Void)? = nil
	) async throws -> QueueJobResult {
		let response = try await submit(model: model, input: input)
		return try await poll(jobId: response.jobId, initialStatus: response.status, onStatusChange: onStatusChange)
	}

	public func submitAndPoll(
		model: VideoModel,
		input: VideoEditInput,
		onStatusChange: ((JobStatusResponse) -> Void)? = nil
	) async throws -> QueueJobResult {
		let response = try await submit(model: model, input: input)
		return try await poll(jobId: response.jobId, initialStatus: response.status, onStatusChange: onStatusChange)
	}

	public func submitAndPoll(
		model: VideoModel,
		input: VideoRestyleInput,
		onStatusChange: ((JobStatusResponse) -> Void)? = nil
	) async throws -> QueueJobResult {
		let response = try await submit(model: model, input: input)
		return try await poll(jobId: response.jobId, initialStatus: response.status, onStatusChange: onStatusChange)
	}

	public func submitAndPoll(
		model: VideoModel,
		input: MotionVideoInput,
		onStatusChange: ((JobStatusResponse) -> Void)? = nil
	) async throws -> QueueJobResult {
		let response = try await submit(model: model, input: input)
		return try await poll(jobId: response.jobId, initialStatus: response.status, onStatusChange: onStatusChange)
	}
}

// MARK: - Private

private extension QueueClient {
	func submitRequest(
		model: VideoModel,
		expectedType: ModelInputType,
		params: [String: Any?],
		files: [(String, FileInput)]
	) async throws -> JobSubmitResponse {
		guard ModelsInputFactory.videoInputType(for: model) == expectedType else {
			throw DecartError.invalidInput("Model \(model.rawValue) does not support this input type")
		}
		let modelDef = Models.video(model)
		guard let endpoint = modelDef.jobsUrlPath else {
			throw DecartError.invalidInput("Queue endpoint is not configured for \(model.rawValue)")
		}

		let boundary = "Boundary-\(UUID().uuidString)"
		var request = makeRequest(path: endpoint, method: "POST")
		request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
		request.httpBody = buildMultipartBody(boundary: boundary, params: params, files: files)

		let (data, response) = try await session.data(for: request)
		try validateResponse(response, data: data, context: "submit")
		return try decode(JobSubmitResponse.self, from: data, context: "submit")
	}

	func poll(
		jobId: String,
		initialStatus: JobStatus,
		onStatusChange: ((JobStatusResponse) -> Void)?
	) async throws -> QueueJobResult {
		let initial = JobStatusResponse(jobId: jobId, status: initialStatus)
		onStatusChange?(initial)

		switch initialStatus {
		case .completed:
			let data = try await result(jobId: jobId)
			return .completed(jobId: jobId, data: data)
		case .failed:
			return .failed(jobId: jobId, error: "Job failed")
		case .pending, .processing:
			break
		}

		try await Task.sleep(for: .milliseconds(500))

		while true {
			let statusResponse = try await status(jobId: jobId)
			onStatusChange?(statusResponse)

			switch statusResponse.status {
			case .pending, .processing:
				try await Task.sleep(for: .milliseconds(1500))
			case .completed:
				let data = try await result(jobId: jobId)
				return .completed(jobId: jobId, data: data)
			case .failed:
				return .failed(jobId: jobId, error: "Job failed")
			}
		}
	}

	func makeRequest(path: String, method: String) -> URLRequest {
		let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
		var request = URLRequest(url: baseURL.appendingPathComponent(cleanPath))
		request.httpMethod = method
		request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
		return request
	}

	func validateResponse(_ response: URLResponse, data: Data, context: String) throws {
		guard let http = response as? HTTPURLResponse else {
			throw DecartError.networkError(URLError(.badServerResponse))
		}
		guard (200...299).contains(http.statusCode) else {
			let body = String(data: data, encoding: .utf8) ?? "Unknown error"
			DecartLogger.log("queue \(context) error: \(body)", level: .error)
			throw DecartError.queueError("Queue \(context) failed: \(http.statusCode) - \(body)")
		}
	}

	func decode<T: Decodable>(_ type: T.Type, from data: Data, context: String) throws -> T {
		do {
			return try JSONDecoder().decode(type, from: data)
		} catch {
			let body = String(data: data, encoding: .utf8) ?? "Unknown"
			DecartLogger.log("queue \(context) decode error: \(body)", level: .error)
			throw DecartError.queueError("Queue \(context) decode failed: \(error.localizedDescription)")
		}
	}

	func buildMultipartBody(boundary: String, params: [String: Any?], files: [(String, FileInput)]) -> Data {
		var body = Data()

		for (key, value) in params {
			guard let value else { continue }
			body.append("--\(boundary)\r\n".data(using: .utf8)!)
			body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
			body.append("\(value)\r\n".data(using: .utf8)!)
		}

		for (fieldName, fileInput) in files {
			body.append("--\(boundary)\r\n".data(using: .utf8)!)
			let filename = fileInput.filename.isEmpty ? "file" : fileInput.filename
			body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
			body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
			body.append(fileInput.data)
			body.append("\r\n".data(using: .utf8)!)
		}

		body.append("--\(boundary)--\r\n".data(using: .utf8)!)
		return body
	}
}
