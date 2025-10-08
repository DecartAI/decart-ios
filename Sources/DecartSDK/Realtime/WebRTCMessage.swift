import Foundation

struct InitializeSessionMessage: Codable {
    let type: String
    let product: String
    let access_key: String
    let session_id: String
    let fps: Int
    let prompt: String?
    let should_enrich: Bool?
    let rotateY: Int?
    
    init(accessKey: String, sessionId: String, fps: Int, prompt: String? = nil, shouldEnrich: Bool? = nil, rotateY: Int? = nil) {
        self.type = "initialize_session"
        self.product = "miragesdk"
        self.access_key = accessKey
        self.session_id = sessionId
        self.fps = fps
        self.prompt = prompt
        self.should_enrich = shouldEnrich
        self.rotateY = rotateY
    }
}

struct OfferMessage: Codable {
    let type: String
    let sdp: String
    
    init(sdp: String) {
        self.type = "offer"
        self.sdp = sdp
    }
}

struct AnswerMessage: Codable {
    let type: String
    let sdp: String
}

struct IceCandidatePayload: Codable {
    let candidate: String
    let sdpMLineIndex: Int32
    let sdpMid: String
}

struct IceCandidateMessage: Codable {
    let type: String
    let candidate: IceCandidatePayload
    
    init(candidate: String, sdpMLineIndex: Int32, sdpMid: String) {
        self.type = "ice-candidate"
        self.candidate = IceCandidatePayload(
            candidate: candidate,
            sdpMLineIndex: sdpMLineIndex,
            sdpMid: sdpMid
        )
    }
}

struct ReadyMessage: Codable {
    let type: String
}

struct PingMessage: Codable {
    let type: String
}

struct PongMessage: Codable {
    let type: String
    
    init() {
        self.type = "pong"
    }
}

struct PromptMessage: Codable {
    let type: String
    let prompt: String
    
    init(prompt: String) {
        self.type = "prompt"
        self.prompt = prompt
    }
}

struct SwitchCameraMessage: Codable {
    let type: String
    let rotateY: Int
    
    init(rotateY: Int) {
        self.type = "switch_camera"
        self.rotateY = rotateY
    }
}

enum IncomingWebRTCMessage: Codable {
    case ready(ReadyMessage)
    case offer(OfferMessage)
    case answer(AnswerMessage)
    case iceCandidate(IceCandidateMessage)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "ready":
            self = .ready(try ReadyMessage(from: decoder))
        case "offer":
            self = .offer(try OfferMessage(from: decoder))
        case "answer":
            self = .answer(try AnswerMessage(from: decoder))
        case "ice-candidate":
            self = .iceCandidate(try IceCandidateMessage(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown message type: \(type)"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        switch self {
        case .ready(let msg):
            try msg.encode(to: encoder)
        case .offer(let msg):
            try msg.encode(to: encoder)
        case .answer(let msg):
            try msg.encode(to: encoder)
        case .iceCandidate(let msg):
            try msg.encode(to: encoder)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
    }
}

enum OutgoingWebRTCMessage: Codable {
    case initializeSession(InitializeSessionMessage)
    case offer(OfferMessage)
    case answer(AnswerMessage)
    case iceCandidate(IceCandidateMessage)
    case prompt(PromptMessage)
    case switchCamera(SwitchCameraMessage)
    
    func encode(to encoder: Encoder) throws {
        switch self {
        case .initializeSession(let msg):
            try msg.encode(to: encoder)
        case .offer(let msg):
            try msg.encode(to: encoder)
        case .answer(let msg):
            try msg.encode(to: encoder)
        case .iceCandidate(let msg):
            try msg.encode(to: encoder)
        case .prompt(let msg):
            try msg.encode(to: encoder)
        case .switchCamera(let msg):
            try msg.encode(to: encoder)
        }
    }
}
