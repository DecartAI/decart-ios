import Foundation
import UniformTypeIdentifiers

public enum ProResolution: String, Codable, Sendable {
	case res720p = "720p"
	case res480p = "480p"
}

public enum DevResolution: String, Codable, Sendable {
	case res720p = "720p"
}

public enum FileInputError: Error, LocalizedError {
	case missingType
	case unsupportedType

	public var errorDescription: String? {
		switch self {
		case .missingType:
			return "Unable to determine the media type. Only image and video files are supported."
		case .unsupportedType:
			return "Unsupported media type. Only image and video files are supported."
		}
	}
}

public struct FileInput: Codable, Sendable {
	public let data: Data
	public let filename: String

	public init(data: Data, filename: String) {
		self.data = data
		self.filename = FileInput.ensureExtension(
			for: filename,
			defaultExtension: FileInput.defaultExtension(forFilename: filename)
		)
	}

	public static func image(data: Data, filename: String = "image.jpg") -> FileInput {
		FileInput(
			data: data,
			filename: ensureExtension(for: filename, defaultExtension: "jpg")
		)
	}

	public static func video(data: Data, filename: String = "video.mp4") -> FileInput {
		FileInput(
			data: data,
			filename: ensureExtension(for: filename, defaultExtension: "mp4")
		)
	}

	public static func from(data: Data, uniformType: UTType?) throws -> FileInput {
		guard let uniformType else {
			throw FileInputError.missingType
		}

		if uniformType.conforms(to: .image) {
			return image(data: data)
		}

		if uniformType.conforms(to: .video) {
			return video(data: data)
		}

		throw FileInputError.unsupportedType
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

	private static func defaultExtension(forFilename filename: String) -> String {
		let pathExtension = (filename as NSString).pathExtension.lowercased()
		switch pathExtension {
		case "jpg", "jpeg", "png", "heic":
			return "jpg"
		case "mp4", "mov", "m4v":
			return "mp4"
		default:
			return "bin"
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
	) {
		self.prompt = prompt
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
	) {
		self.prompt = prompt
		self.seed = seed
		self.resolution = resolution
		self.orientation = orientation
	}
}

public struct ImageToVideoInput: Codable, Sendable {
	public let prompt: String
	public let data: FileInput  // We need to handle how this is serialized (e.g. multipart or base64)
	public let seed: Int?
	public let resolution: ProResolution?  // Or separate structs for dev/pro if needed, but factory can handle types

	public init(
		prompt: String,
		data: FileInput,
		seed: Int? = nil,
		resolution: ProResolution? = .res720p
	) {
		self.prompt = prompt
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
	) {
		self.prompt = prompt
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
	public let resolution: ProResolution?  // pro supports 480p/720p, dev supports 720p.
	public let enhancePrompt: Bool?
	public let numInferenceSteps: Int?

	public init(
		prompt: String,
		data: FileInput,
		seed: Int? = nil,
		resolution: ProResolution? = .res720p,
		enhancePrompt: Bool? = nil,
		numInferenceSteps: Int? = nil
	) {
		self.prompt = prompt
		self.data = data
		self.seed = seed
		self.resolution = resolution
		self.enhancePrompt = enhancePrompt
		self.numInferenceSteps = numInferenceSteps
	}
}

public enum ModelInputType {
	case textToVideo
	case textToImage
	case imageToVideo
	case imageToImage
	case videoToVideo
}

public enum ModelsInputFactory {
	public static func videoInputType(for model: VideoModel) -> ModelInputType {
		switch model {
		case .lucy_pro_t2v:
			return .textToVideo
		case .lucy_dev_i2v, .lucy_pro_i2v:
			return .imageToVideo
		case .lucy_dev_v2v, .lucy_pro_v2v:
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
