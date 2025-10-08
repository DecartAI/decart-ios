import Foundation

public enum RealtimeModel: String, CaseIterable {
    case mirage
    case lucy_v2v_720p_rt
}

public struct ModelDefinition {
    public let name: String
    public let urlPath: String
    public let fps: Int
    public let width: Int
    public let height: Int
    
    public init(name: String, urlPath: String, fps: Int, width: Int, height: Int) {
        self.name = name
        self.urlPath = urlPath
        self.fps = fps
        self.width = width
        self.height = height
    }
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
}
