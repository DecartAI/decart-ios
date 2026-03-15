import Foundation

public enum VideoCodec: String {
	case vp8 = "video/VP8"
	case h264 = "video/H264"
}

public enum RealtimeModel: String, CaseIterable {
	case mirage
	case mirage_v2
	case lucy_v2v_720p_rt
	case lucy_2_rt
}

public enum ImageModel: String, CaseIterable {
	case lucy_pro_t2i = "lucy-pro-t2i"
	case lucy_pro_i2i = "lucy-pro-i2i"
}

public enum VideoModel: String, CaseIterable {
	case lucy_dev_i2v = "lucy-dev-i2v"
	case lucy_fast_v2v = "lucy-fast-v2v"
	case lucy_pro_t2v = "lucy-pro-t2v"
	case lucy_pro_i2v = "lucy-pro-i2v"
	case lucy_pro_v2v = "lucy-pro-v2v"
	case lucy_2_v2v = "lucy-2-v2v"
	case lucy_restyle_v2v = "lucy-restyle-v2v"
	case lucy_motion = "lucy-motion"

}

public enum Models {
	public static func realtime(_ model: RealtimeModel) -> ModelDefinition {
		switch model {
		case .mirage:
			return ModelDefinition(
				name: "mirage",
				urlPath: "/v1/stream",
				fps: 25,
				width: 1280,
				height: 704
			)
		case .mirage_v2:
			return ModelDefinition(
				name: "mirage_v2",
				urlPath: "/v1/stream",
				fps: 22,
				width: 1280,
				height: 704
			)
		case .lucy_v2v_720p_rt:
			return ModelDefinition(
				name: "lucy_v2v_720p_rt",
				urlPath: "/v1/stream",
				fps: 25,
				width: 1280,
				height: 704
			)
		case .lucy_2_rt:
			return ModelDefinition(
				name: "lucy_2_rt",
				urlPath: "/v1/stream",
				fps: 20,
				width: 1280,
				height: 720,
				hasReferenceImage: true
			)

		}
	}

	public static func image(_ model: ImageModel) -> ModelDefinition {
		switch model {
		case .lucy_pro_t2i:
			return ModelDefinition(
				name: "lucy-pro-t2i",
				urlPath: "/v1/generate/lucy-pro-t2i",
				fps: 25,
				width: 1280,
				height: 704
			)
		case .lucy_pro_i2i:
			return ModelDefinition(
				name: "lucy-pro-i2i",
				urlPath: "/v1/generate/lucy-pro-i2i",
				fps: 25,
				width: 1280,
				height: 704
			)
		}
	}

	public static func video(_ model: VideoModel) -> ModelDefinition {
		switch model {
		case .lucy_dev_i2v:
			return ModelDefinition(
				name: "lucy-dev-i2v",
				urlPath: "/v1/generate/lucy-dev-i2v",
				jobsUrlPath: "/v1/jobs/lucy-dev-i2v",
				fps: 25,
				width: 1280,
				height: 704
			)
		case .lucy_fast_v2v:
			return ModelDefinition(
				name: "lucy-fast-v2v",
				urlPath: "/v1/generate/lucy-fast-v2v",
				jobsUrlPath: "/v1/jobs/lucy-fast-v2v",
				fps: 25,
				width: 1280,
				height: 704
			)
		case .lucy_pro_t2v:
			return ModelDefinition(
				name: "lucy-pro-t2v",
				urlPath: "/v1/generate/lucy-pro-t2v",
				jobsUrlPath: "/v1/jobs/lucy-pro-t2v",
				fps: 25,
				width: 1280,
				height: 704
			)
		case .lucy_pro_i2v:
			return ModelDefinition(
				name: "lucy-pro-i2v",
				urlPath: "/v1/generate/lucy-pro-i2v",
				jobsUrlPath: "/v1/jobs/lucy-pro-i2v",
				fps: 25,
				width: 1280,
				height: 704
			)
		case .lucy_pro_v2v:
			return ModelDefinition(
				name: "lucy-pro-v2v",
				urlPath: "/v1/generate/lucy-pro-v2v",
				jobsUrlPath: "/v1/jobs/lucy-pro-v2v",
				fps: 25,
				width: 1280,
				height: 704
			)
		case .lucy_2_v2v:
			return ModelDefinition(
				name: "lucy-2-v2v",
				urlPath: "/v1/generate/lucy-2-v2v",
				jobsUrlPath: "/v1/jobs/lucy-2-v2v",
				fps: 20,
				width: 1280,
				height: 720
			)
		case .lucy_restyle_v2v:
			return ModelDefinition(
				name: "lucy-restyle-v2v",
				urlPath: "/v1/generate/lucy-restyle-v2v",
				jobsUrlPath: "/v1/jobs/lucy-restyle-v2v",
				fps: 25,
				width: 1280,
				height: 704
			)
		case .lucy_motion:
			return ModelDefinition(
				name: "lucy-motion",
				urlPath: "/v1/generate/lucy-motion",
				jobsUrlPath: "/v1/jobs/lucy-motion",
				fps: 25,
				width: 1280,
				height: 704
			)

		}
	}
}
