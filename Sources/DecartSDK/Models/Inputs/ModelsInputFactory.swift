public enum ModelInputType: Sendable {
	case imageToImage
	case videoToVideo
}

public enum ModelsInputFactory: Sendable {
	public static func videoInputType(for model: VideoModel) -> ModelInputType {
		switch model {
		case .lucy_pro_v2v:
			return .videoToVideo
		}
	}

	public static func imageInputType(for model: ImageModel) -> ModelInputType {
		switch model {
		case .lucy_pro_i2i:
			return .imageToImage
		}
	}
}
