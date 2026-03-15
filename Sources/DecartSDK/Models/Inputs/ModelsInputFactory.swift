public enum ModelInputType: Sendable {
	case textToVideo
	case textToImage
	case imageToVideo
	case imageToImage
	case videoToVideo
	case videoEdit
	case videoRestyle
	case motionVideo

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
		case .lucy_2_v2v:
			return .videoEdit
		case .lucy_restyle_v2v:
			return .videoRestyle
		case .lucy_motion:
			return .motionVideo

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
