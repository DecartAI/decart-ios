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
		case .lucyClip, .lucyClipLatest, .lucy_pro_v2v:
			return .videoToVideo
		case .lucy2, .lucy2_1, .lucy2_1_vton, .lucyLatest, .lucyVtonLatest, .lucy_2_v2v:
			return .videoEdit
		case .lucyRestyle2, .lucyRestyleLatest, .lucy_restyle_v2v:
			return .videoRestyle
		case .lucyMotion, .lucyMotionLatest:
			return .motionVideo
		}
	}

	public static func imageInputType(for model: ImageModel) -> ModelInputType {
		switch model {
		case .lucyImage2, .lucyImageLatest, .lucy_pro_i2i:
			return .imageToImage
		}
	}
}
