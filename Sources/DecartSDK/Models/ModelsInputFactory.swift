import Foundation
import UniformTypeIdentifiers

public enum ProResolution: String, Codable, Sendable {
	case res720p = "720p"
	case res480p = "480p"
}

public enum DevResolution: String, Codable, Sendable {
	case res720p = "720p"
}

public enum InputValidationError: LocalizedError {
	case emptyPrompt
	case emptyFileData
	case expectedImage
	case expectedVideo
	case unsupportedMediaType

	public var errorDescription: String? {
		switch self {
		case .emptyPrompt:
			return "Prompt cannot be empty"
		case .emptyFileData:
			return "File data cannot be empty"
		case .expectedImage:
			return "Expected an image file"
		case .expectedVideo:
			return "Expected a video file"
		case .unsupportedMediaType:
			return "Unsupported media type. Only image and video files are supported"
		}
	}
}

public enum MediaType: Sendable {
	case image
	case video
}

public struct FileInput: Codable, Sendable {
	public let data: Data
	public let filename: String
	public let mediaType: MediaType

	private enum CodingKeys: String, CodingKey {
		case data, filename
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.data = try container.decode(Data.self, forKey: .data)
		self.filename = try container.decode(String.self, forKey: .filename)
		self.mediaType = FileInput.inferMediaType(from: filename)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(data, forKey: .data)
		try container.encode(filename, forKey: .filename)
	}

	private init(data: Data, filename: String, mediaType: MediaType) {
		self.data = data
		self.filename = filename
		self.mediaType = mediaType
	}

	public static func image(data: Data, filename: String = "image.jpg") throws -> FileInput {
		guard !data.isEmpty else { throw InputValidationError.emptyFileData }
		return FileInput(
			data: data,
			filename: ensureExtension(for: filename, defaultExtension: "jpg"),
			mediaType: .image
		)
	}

	public static func video(data: Data, filename: String = "video.mp4") throws -> FileInput {
		guard !data.isEmpty else { throw InputValidationError.emptyFileData }
		return FileInput(
			data: data,
			filename: ensureExtension(for: filename, defaultExtension: "mp4"),
			mediaType: .video
		)
	}

	public static func from(data: Data, uniformType: UTType?) throws -> FileInput {
		guard !data.isEmpty else { throw InputValidationError.emptyFileData }

		if let type = uniformType, type.conforms(to: .image) {
			return try image(data: data)
		}

		if let type = uniformType, type.conforms(to: .video) || type.conforms(to: .movie) {
			return try video(data: data)
		}

		throw InputValidationError.unsupportedMediaType
	}

	private static func ensureExtension(for filename: String, defaultExtension: String) -> String {
		var trimmed = (filename as NSString).lastPathComponent
		if trimmed.isEmpty {
			trimmed = "attachment.\(defaultExtension)"
		}

		if (trimmed as NSString).pathExtension.isEmpty {
			trimmed.append(".\(defaultExtension)")
		}

		return trimmed
	}

	private static func inferMediaType(from filename: String) -> MediaType {
		let ext = (filename as NSString).pathExtension.lowercased()
		switch ext {
		case "jpg", "jpeg", "png", "heic", "webp":
			return .image
		default:
			return .video
		}
	}
}

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

public enum ModelInputType: Sendable {
	case textToVideo
	case textToImage
	case imageToVideo
	case imageToImage
	case videoToVideo
}

public enum ModelsInputFactory: Sendable {
	public static func videoInputType(for model: VideoModel) -> ModelInputType {
		switch model {
		case .lucy_pro_t2v:
			return .textToVideo
		case .lucy_dev_i2v, .lucy_pro_i2v:
			return .imageToVideo
		case .lucy_fast_v2v, .lucy_pro_v2v:
			return .videoToVideo
		}
	}

	public static func imageInputType(for model: ImageModel) -> ModelInputType {
		switch model {
		case .lucy_pro_t2i:
			return .textToImage
		case .lucy_pro_i2i:
			return .imageToImage
		}
	}
}
