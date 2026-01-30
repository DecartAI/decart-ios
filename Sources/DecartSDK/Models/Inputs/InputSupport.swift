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
