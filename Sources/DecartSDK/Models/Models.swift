import Foundation
import os.log

private let logger = Logger(subsystem: "ai.decart.sdk", category: "Models")
private let warnedAliasesLock = NSLock()
private nonisolated(unsafe) var warnedAliases: Set<String> = []

private func warnDeprecated(_ oldName: String, canonical: String) {
	let shouldWarn: Bool = warnedAliasesLock.withLock {
		guard !warnedAliases.contains(oldName) else { return false }
		warnedAliases.insert(oldName)
		return true
	}
	if shouldWarn {
		logger.warning("[Decart SDK] Model \"\(oldName)\" is deprecated. Use \"\(canonical)\" instead. See https://docs.platform.decart.ai/models for details.")
	}
}

public enum VideoCodec: String, Sendable {
	case vp8 = "video/VP8"
	case h264 = "video/H264"
}

public enum RealtimeModel: String, CaseIterable {
	// Canonical names
	case lucyRestyle2 = "lucy-restyle-2"
	case lucy2_1 = "lucy-2.1"
	case lucy2_1_vton = "lucy-2.1-vton"
	case lucyVton2 = "lucy-vton-2"
	case lucyVton3 = "lucy-vton-3"
	// Latest aliases (server-side resolution)
	case lucyLatest = "lucy-latest"
	case lucyVtonLatest = "lucy-vton-latest"
	case lucyRestyleLatest = "lucy-restyle-latest"

	// Deprecated aliases
	@available(*, deprecated, renamed: "lucyRestyle2")
	case mirage_v2 = "mirage_v2"
	@available(*, deprecated, renamed: "lucy2_1_vton")
	case lucyVton = "lucy-vton"
	@available(*, deprecated, renamed: "lucyVton2")
	case lucy2_1_vton_2 = "lucy-2.1-vton-2"

	public static var allCases: [RealtimeModel] {
		[.lucy2_1, .lucy2_1_vton, .lucyVton2, .lucyVton3, .lucyRestyle2, .lucyLatest, .lucyVtonLatest, .lucyRestyleLatest]
	}
}

public enum ImageModel: String, CaseIterable, Sendable {
	// Canonical names
	case lucyImage2 = "lucy-image-2"
	// Latest alias (server-side resolution)
	case lucyImageLatest = "lucy-image-latest"

	// Deprecated aliases
	@available(*, deprecated, renamed: "lucyImage2")
	case lucy_pro_i2i = "lucy-pro-i2i"

	public static var allCases: [ImageModel] {
		[.lucyImage2, .lucyImageLatest]
	}
}

public enum VideoModel: String, CaseIterable, Sendable {
	// Canonical names
	case lucyClip = "lucy-clip"
	case lucy2_1 = "lucy-2.1"
	case lucyRestyle2 = "lucy-restyle-2"
	case lucy2_1_vton = "lucy-2.1-vton"
	case lucyVton2 = "lucy-vton-2"
	case lucyVton3 = "lucy-vton-3"
	// Latest aliases (server-side resolution)
	case lucyLatest = "lucy-latest"
	case lucyVtonLatest = "lucy-vton-latest"
	case lucyRestyleLatest = "lucy-restyle-latest"
	case lucyClipLatest = "lucy-clip-latest"

	// Deprecated aliases
	@available(*, deprecated, renamed: "lucyClip")
	case lucy_pro_v2v = "lucy-pro-v2v"
	@available(*, deprecated, renamed: "lucyRestyle2")
	case lucy_restyle_v2v = "lucy-restyle-v2v"
	@available(*, deprecated, renamed: "lucy2_1_vton")
	case lucyVton = "lucy-vton"
	@available(*, deprecated, renamed: "lucyVton2")
	case lucy2_1_vton_2 = "lucy-2.1-vton-2"

	public static var allCases: [VideoModel] {
		[.lucyClip, .lucy2_1, .lucy2_1_vton, .lucyVton2, .lucyVton3, .lucyRestyle2, .lucyLatest, .lucyVtonLatest, .lucyRestyleLatest, .lucyClipLatest]
	}
}

public enum Models {
	public static func realtime(_ model: RealtimeModel) -> ModelDefinition {
		switch model {
		case .lucyRestyle2:
			return ModelDefinition(
				name: "lucy-restyle-2",
				urlPath: "/v1/stream",
				fps: 30,
				width: 1280,
				height: 704
			)
		case .lucy2_1:
			return ModelDefinition(
				name: "lucy-2.1",
				urlPath: "/v1/stream",
				fps: 30,
				width: 1088,
				height: 624,
				hasReferenceImage: true
			)
		case .lucy2_1_vton:
			return ModelDefinition(
				name: "lucy-2.1-vton",
				urlPath: "/v1/stream",
				fps: 30,
				width: 1088,
				height: 624,
				hasReferenceImage: true
			)
		case .lucyVton2:
			return ModelDefinition(
				name: "lucy-vton-2",
				urlPath: "/v1/stream",
				fps: 30,
				width: 1088,
				height: 624,
				hasReferenceImage: true
			)
		case .lucyVton3:
			return ModelDefinition(
				name: "lucy-vton-3",
				urlPath: "/v1/stream",
				fps: 30,
				width: 1088,
				height: 624,
				hasReferenceImage: true
			)
		case .lucyLatest:
			return ModelDefinition(
				name: "lucy-latest",
				urlPath: "/v1/stream",
				fps: 30,
				width: 1088,
				height: 624,
				hasReferenceImage: true
			)
		case .lucyVtonLatest:
			return ModelDefinition(
				name: "lucy-vton-latest",
				urlPath: "/v1/stream",
				fps: 30,
				width: 1088,
				height: 624,
				hasReferenceImage: true
			)
		case .lucyRestyleLatest:
			return ModelDefinition(
				name: "lucy-restyle-latest",
				urlPath: "/v1/stream",
				fps: 30,
				width: 1280,
				height: 704
			)
		case .mirage_v2:
			warnDeprecated("mirage_v2", canonical: "lucy-restyle-2")
			return ModelDefinition(
				name: "mirage_v2",
				urlPath: "/v1/stream",
				fps: 30,
				width: 1280,
				height: 704
			)
		case .lucyVton:
			warnDeprecated("lucy-vton", canonical: "lucy-2.1-vton")
			return ModelDefinition(
				name: "lucy-vton",
				urlPath: "/v1/stream",
				fps: 30,
				width: 1088,
				height: 624,
				hasReferenceImage: true
			)
		case .lucy2_1_vton_2:
			warnDeprecated("lucy-2.1-vton-2", canonical: "lucy-vton-2")
			return ModelDefinition(
				name: "lucy-2.1-vton-2",
				urlPath: "/v1/stream",
				fps: 30,
				width: 1088,
				height: 624,
				hasReferenceImage: true
			)
		}
	}

	public static func image(_ model: ImageModel) -> ModelDefinition {
		switch model {
		case .lucyImage2:
			return ModelDefinition(
				name: "lucy-image-2",
				urlPath: "/v1/generate/lucy-image-2",
				fps: 25,
				width: 1280,
				height: 704
			)
		case .lucyImageLatest:
			return ModelDefinition(
				name: "lucy-image-latest",
				urlPath: "/v1/generate/lucy-image-latest",
				fps: 25,
				width: 1280,
				height: 704
			)
		case .lucy_pro_i2i:
			warnDeprecated("lucy-pro-i2i", canonical: "lucy-image-2")
			return ModelDefinition(
				name: "lucy-pro-i2i",
				urlPath: "/v1/generate/lucy-pro-i2i",
				jobsUrlPath: "/v1/jobs/lucy-pro-i2i",
				fps: 25,
				width: 1280,
				height: 704
			)
		}
	}

	public static func video(_ model: VideoModel) -> ModelDefinition {
		switch model {
		case .lucyClip:
			return ModelDefinition(
				name: "lucy-clip",
				urlPath: "/v1/generate/lucy-clip",
				jobsUrlPath: "/v1/jobs/lucy-clip",
				fps: 25,
				width: 1280,
				height: 704
			)
		case .lucy2_1:
			return ModelDefinition(
				name: "lucy-2.1",
				urlPath: "/v1/generate/lucy-2.1",
				jobsUrlPath: "/v1/jobs/lucy-2.1",
				fps: 20,
				width: 1088,
				height: 624
			)
		case .lucy2_1_vton:
			return ModelDefinition(
				name: "lucy-2.1-vton",
				urlPath: "/v1/generate/lucy-2.1-vton",
				jobsUrlPath: "/v1/jobs/lucy-2.1-vton",
				fps: 20,
				width: 1088,
				height: 624
			)
		case .lucyVton2:
			return ModelDefinition(
				name: "lucy-vton-2",
				urlPath: "/v1/generate/lucy-vton-2",
				jobsUrlPath: "/v1/jobs/lucy-vton-2",
				fps: 20,
				width: 1088,
				height: 624
			)
		case .lucyVton3:
			return ModelDefinition(
				name: "lucy-vton-3",
				urlPath: "/v1/generate/lucy-vton-3",
				jobsUrlPath: "/v1/jobs/lucy-vton-3",
				fps: 20,
				width: 1088,
				height: 624
			)
		case .lucyRestyle2:
			return ModelDefinition(
				name: "lucy-restyle-2",
				urlPath: "/v1/generate/lucy-restyle-2",
				jobsUrlPath: "/v1/jobs/lucy-restyle-2",
				fps: 22,
				width: 1280,
				height: 704
			)
		case .lucyLatest:
			return ModelDefinition(
				name: "lucy-latest",
				urlPath: "/v1/generate/lucy-latest",
				jobsUrlPath: "/v1/jobs/lucy-latest",
				fps: 20,
				width: 1088,
				height: 624
			)
		case .lucyVtonLatest:
			return ModelDefinition(
				name: "lucy-vton-latest",
				urlPath: "/v1/generate/lucy-vton-latest",
				jobsUrlPath: "/v1/jobs/lucy-vton-latest",
				fps: 20,
				width: 1088,
				height: 624
			)
		case .lucyRestyleLatest:
			return ModelDefinition(
				name: "lucy-restyle-latest",
				urlPath: "/v1/generate/lucy-restyle-latest",
				jobsUrlPath: "/v1/jobs/lucy-restyle-latest",
				fps: 22,
				width: 1280,
				height: 704
			)
		case .lucyClipLatest:
			return ModelDefinition(
				name: "lucy-clip-latest",
				urlPath: "/v1/generate/lucy-clip-latest",
				jobsUrlPath: "/v1/jobs/lucy-clip-latest",
				fps: 25,
				width: 1280,
				height: 704
			)
		case .lucy_pro_v2v:
			warnDeprecated("lucy-pro-v2v", canonical: "lucy-clip")
			return ModelDefinition(
				name: "lucy-pro-v2v",
				urlPath: "/v1/generate/lucy-pro-v2v",
				jobsUrlPath: "/v1/jobs/lucy-pro-v2v",
				fps: 25,
				width: 1280,
				height: 704
			)
		case .lucy_restyle_v2v:
			warnDeprecated("lucy-restyle-v2v", canonical: "lucy-restyle-2")
			return ModelDefinition(
				name: "lucy-restyle-v2v",
				urlPath: "/v1/generate/lucy-restyle-v2v",
				jobsUrlPath: "/v1/jobs/lucy-restyle-v2v",
				fps: 22,
				width: 1280,
				height: 704
			)
		case .lucyVton:
			warnDeprecated("lucy-vton", canonical: "lucy-2.1-vton")
			return ModelDefinition(
				name: "lucy-vton",
				urlPath: "/v1/generate/lucy-vton",
				jobsUrlPath: "/v1/jobs/lucy-vton",
				fps: 20,
				width: 1088,
				height: 624
			)
		case .lucy2_1_vton_2:
			warnDeprecated("lucy-2.1-vton-2", canonical: "lucy-vton-2")
			return ModelDefinition(
				name: "lucy-2.1-vton-2",
				urlPath: "/v1/generate/lucy-2.1-vton-2",
				jobsUrlPath: "/v1/jobs/lucy-2.1-vton-2",
				fps: 20,
				width: 1088,
				height: 624
			)
		}
	}
}
