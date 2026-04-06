public enum ModelInputType: Sendable {
	case imageToImage
	case videoToVideo
	case videoEdit
	case videoRestyle
	case motionVideo

}

public enum ModelsInputFactory: Sendable {
	public static func videoInputType(for model: VideoModel) -> ModelInputType {
		switch model {
		case .lucyClip, .lucy_pro_v2v:
			return .videoToVideo
		case .lucy2, .lucy2_1, .lucy_2_v2v:
			return .videoEdit
		case .lucyRestyle2, .lucy_restyle_v2v:
			return .videoRestyle
		case .lucyMotion:
			return .motionVideo
		}
	}

	public static func imageInputType(for model: ImageModel) -> ModelInputType {
		switch model {
		case .lucyImage2, .lucy_pro_i2i:
			return .imageToImage
		}
	}
}
