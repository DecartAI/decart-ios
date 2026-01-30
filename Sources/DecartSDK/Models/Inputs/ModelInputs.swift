import Foundation

public struct TextToVideoInput: Codable, Sendable {
	public let prompt: String
	public let seed: Int?
	public let resolution: ProResolution?
	public let orientation: String?

	public init(
		prompt: String,
		seed: Int? = nil,
		resolution: ProResolution? = .res720p,
		orientation: String? = nil
	) throws {
		let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { throw InputValidationError.emptyPrompt }

		self.prompt = trimmed
		self.seed = seed
		self.resolution = resolution
		self.orientation = orientation
	}
}

public struct TextToImageInput: Codable, Sendable {
	public let prompt: String
	public let seed: Int?
	public let resolution: ProResolution?
	public let orientation: String?

	public init(
		prompt: String,
		seed: Int? = nil,
		resolution: ProResolution? = .res720p,
		orientation: String? = nil
	) throws {
		let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { throw InputValidationError.emptyPrompt }

		self.prompt = trimmed
		self.seed = seed
		self.resolution = resolution
		self.orientation = orientation
	}
}

public struct ImageToVideoInput: Codable, Sendable {
	public let prompt: String
	public let data: FileInput
	public let seed: Int?
	public let resolution: ProResolution?

	public init(
		prompt: String,
		data: FileInput,
		seed: Int? = nil,
		resolution: ProResolution? = .res720p
	) throws {
		let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { throw InputValidationError.emptyPrompt }
		guard data.mediaType == .image else { throw InputValidationError.expectedImage }

		self.prompt = trimmed
		self.data = data
		self.seed = seed
		self.resolution = resolution
	}
}

public struct ImageToImageInput: Codable, Sendable {
	public let prompt: String
	public let data: FileInput
	public let seed: Int?
	public let resolution: ProResolution?
	public let enhancePrompt: Bool?

	public init(
		prompt: String,
		data: FileInput,
		seed: Int? = nil,
		resolution: ProResolution? = .res720p,
		enhancePrompt: Bool? = nil
	) throws {
		let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { throw InputValidationError.emptyPrompt }
		guard data.mediaType == .image else { throw InputValidationError.expectedImage }

		self.prompt = trimmed
		self.data = data
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
