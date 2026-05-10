import Foundation

public struct ImageToImageInput: Codable, Sendable {
	public let prompt: String
	public let data: FileInput
	public let referenceImage: FileInput?
	public let seed: Int?
	public let resolution: ProResolution?
	public let enhancePrompt: Bool?

	public init(
		prompt: String,
		data: FileInput,
		referenceImage: FileInput? = nil,
		seed: Int? = nil,
		resolution: ProResolution? = .res720p,
		enhancePrompt: Bool? = nil
	) throws {
		let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { throw InputValidationError.emptyPrompt }
		guard data.mediaType == .image else { throw InputValidationError.expectedImage }
		if let ref = referenceImage {
			guard ref.mediaType == .image else { throw InputValidationError.expectedImage }
		}

		self.prompt = trimmed
		self.data = data
		self.referenceImage = referenceImage
		self.seed = seed
		self.resolution = resolution
		self.enhancePrompt = enhancePrompt
	}
}

public struct VideoToVideoInput: Codable, Sendable {
	public let prompt: String
	public let data: FileInput
	public let seed: Int?
	public let resolution: ProResolution?
	public let enhancePrompt: Bool?
	public let numInferenceSteps: Int?

	public init(
		prompt: String,
		data: FileInput,
		seed: Int? = nil,
		resolution: ProResolution? = .res720p,
		enhancePrompt: Bool? = nil,
		numInferenceSteps: Int? = nil
	) throws {
		let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { throw InputValidationError.emptyPrompt }
		guard data.mediaType == .video else { throw InputValidationError.expectedVideo }

		self.prompt = trimmed
		self.data = data
		self.seed = seed
		self.resolution = resolution
		self.enhancePrompt = enhancePrompt
		self.numInferenceSteps = numInferenceSteps
	}
}

public struct VideoEditInput: Codable, Sendable {
	public let prompt: String
	public let data: FileInput
	public let referenceImage: FileInput?
	public let seed: Int?
	public let resolution: ProResolution?
	public let enhancePrompt: Bool?

	public init(
		prompt: String,
		data: FileInput,
		referenceImage: FileInput? = nil,
		seed: Int? = nil,
		resolution: ProResolution? = .res720p,
		enhancePrompt: Bool? = nil
	) throws {
		let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { throw InputValidationError.emptyPrompt }
		guard data.mediaType == .video else { throw InputValidationError.expectedVideo }
		if let ref = referenceImage {
			guard ref.mediaType == .image else { throw InputValidationError.expectedImage }
		}

		self.prompt = trimmed
		self.data = data
		self.referenceImage = referenceImage
		self.seed = seed
		self.resolution = resolution
		self.enhancePrompt = enhancePrompt
	}
}

public struct VideoRestyleInput: Codable, Sendable {
	public let prompt: String?
	public let data: FileInput
	public let referenceImage: FileInput?
	public let seed: Int?
	public let resolution: ProResolution?
	public let enhancePrompt: Bool?

	public init(
		prompt: String? = nil,
		data: FileInput,
		referenceImage: FileInput? = nil,
		seed: Int? = nil,
		resolution: ProResolution? = .res720p,
		enhancePrompt: Bool? = nil
	) throws {
		guard data.mediaType == .video else { throw InputValidationError.expectedVideo }

		let hasPrompt = prompt != nil && !prompt!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		let hasRef = referenceImage != nil
		guard hasPrompt || hasRef else {
			throw InputValidationError.restyleMissingInput
		}
		guard !(hasPrompt && hasRef) else {
			throw InputValidationError.restyleMutuallyExclusive
		}
		if let ref = referenceImage {
			guard ref.mediaType == .image else { throw InputValidationError.expectedImage }
		}

		self.prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
		self.data = data
		self.referenceImage = referenceImage
		self.seed = seed
		self.resolution = resolution
		self.enhancePrompt = hasPrompt ? enhancePrompt : nil
	}
}

