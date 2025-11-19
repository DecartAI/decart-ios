import Foundation

public enum VideoCodec: String {
	case vp8 = "video/VP8"
	case h264 = "video/H264"
}

public enum RealtimeModel: String, CaseIterable {
	case mirage
	case mirage_v2
	case lucy_v2v_720p_rt
}

public enum ImageModel: String, CaseIterable {
	case lucy_edit_ani
	case mirage
	case mirage_v2
}

public enum VideoModel: String, CaseIterable {
	case lucy_v2v_720p_rt
	case lucy_edit_ani
	case mirage
	case mirage_v2
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
		}
	}

//	public static func image(_ model: String) -> ModelDefinition {}
//	public static func video(_ model: VideoModel) -> ModelDefinition {}
}
