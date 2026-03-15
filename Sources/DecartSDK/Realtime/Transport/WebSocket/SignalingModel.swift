//
//  SignalingModel.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 03/11/2025.
//

import Foundation
import WebRTC

struct InitializeConnectionMessage: Codable, Sendable {
	let type: String
	let apiKey: String
	let model: String

	let initialPrompt: String?
}

struct OfferMessage: Codable, Sendable {
	let type: String
	let sdp: String

	init(sdp: String) {
		self.type = "offer"
		self.sdp = sdp
	}
}

struct AnswerMessage: Codable, Sendable {
	let type: String
	let sdp: String
}

struct IceCandidatePayload: Codable, Sendable {
	let candidate: String
	let sdpMLineIndex: Int32
	let sdpMid: String
}

struct IceCandidateMessage: Codable, Sendable {
	let type: String
	let candidate: IceCandidatePayload

	init(candidate: RTCIceCandidate) {
		guard let sdpMid = candidate.sdpMid else {
			fatalError("found invalid candidate without sdpMid")
		}

		self.type = "ice-candidate"
		self.candidate = IceCandidatePayload(
			candidate: candidate.sdp,
			sdpMLineIndex: candidate.sdpMLineIndex,
			sdpMid: sdpMid
		)
	}
}

struct PromptMessage: Encodable, Sendable {
	let type: String
	let prompt: String
	let enhancePrompt: Bool?

	init(prompt: String, enhancePrompt: Bool? = nil) {
		self.type = "prompt"
		self.prompt = prompt
		self.enhancePrompt = enhancePrompt
	}

	private enum CodingKeys: String, CodingKey {
		case type
		case prompt
		case enhancePrompt = "enhance_prompt"
	}
}

struct SetImageMessage: Encodable, Sendable {
	let type: String
	let prompt: String?
	let imageData: String?
	let enhancePrompt: Bool?
	private let encodeNullPrompt: Bool
	private let encodeNullImageData: Bool

	init(
		imageData: String?,
		prompt: String? = nil,
		enhancePrompt: Bool? = nil,
		encodeNullPrompt: Bool = false,
		encodeNullImageData: Bool = false
	) {
		self.type = "set_image"
		self.prompt = prompt
		self.imageData = imageData
		self.enhancePrompt = enhancePrompt
		self.encodeNullPrompt = encodeNullPrompt
		self.encodeNullImageData = encodeNullImageData
	}

	static func passthrough() -> SetImageMessage {
		SetImageMessage(
			imageData: nil,
			prompt: nil,
			encodeNullPrompt: true,
			encodeNullImageData: true
		)
	}

	private enum CodingKeys: String, CodingKey {
		case type
		case prompt
		case imageData = "image_data"
		case enhancePrompt = "enhance_prompt"
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(type, forKey: .type)

		if let prompt {
			try container.encode(prompt, forKey: .prompt)
		} else if encodeNullPrompt {
			try container.encodeNil(forKey: .prompt)
		}

		if let imageData {
			try container.encode(imageData, forKey: .imageData)
		} else if encodeNullImageData {
			try container.encodeNil(forKey: .imageData)
		}

		if let enhancePrompt {
			try container.encode(enhancePrompt, forKey: .enhancePrompt)
		}
	}
}

struct ServerErrorMessage: Codable, Sendable {
	let type: String
	let message: String?
	let error: String?
}

struct SessionIdMessage: Codable, Sendable {
	let type: String
	let sessionId: String?
	let session_id: String?

	var id: String? { sessionId ?? session_id }
}

struct GenerationStartedMessage: Codable, Sendable {
	let type: String
}

struct GenerationTickMessage: Codable, Sendable {
	let type: String
	let seconds: Double
}

struct GenerationEndedMessage: Codable, Sendable {
	let type: String
	let seconds: Double?
	let reason: String?
}

struct PromptAckMessage: Codable, Sendable {
	let type: String
	let prompt: String?
	let success: Bool?
	let error: String?
}

struct SetImageAckMessage: Codable, Sendable {
	let type: String
	let success: Bool?
	let error: String?
}

struct StatusMessage: Codable, Sendable {
	let type: String
	let status: String
}

struct QueuePositionMessage: Codable, Sendable {
	let type: String
	let queuePosition: Int?
	let queueSize: Int?

	private enum CodingKeys: String, CodingKey {
		case type
		case queuePosition = "queue_position"
		case queueSize = "queue_size"
	}
}

enum IncomingWebSocketMessage: Codable, Sendable {
	case offer(OfferMessage)
	case answer(AnswerMessage)
	case iceCandidate(IceCandidateMessage)
	case error(ServerErrorMessage)
	case sessionId(SessionIdMessage)
	case generationStarted(GenerationStartedMessage)
	case generationTick(GenerationTickMessage)
	case generationEnded(GenerationEndedMessage)
	case promptAck(PromptAckMessage)
	case setImageAck(SetImageAckMessage)
	case status(StatusMessage)
	case queuePosition(QueuePositionMessage)

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let type = try container.decode(String.self, forKey: .type)

		switch type {
		case "offer":
			self = try .offer(OfferMessage(from: decoder))
		case "answer":
			self = try .answer(AnswerMessage(from: decoder))
		case "ice-candidate":
			self = try .iceCandidate(IceCandidateMessage(from: decoder))
		case "error":
			self = try .error(ServerErrorMessage(from: decoder))
		case "session_id":
			self = try .sessionId(SessionIdMessage(from: decoder))
		case "generation_started":
			self = try .generationStarted(GenerationStartedMessage(from: decoder))
		case "generation_tick":
			self = try .generationTick(GenerationTickMessage(from: decoder))
		case "generation_ended":
			self = try .generationEnded(GenerationEndedMessage(from: decoder))
		case "prompt_ack":
			self = try .promptAck(PromptAckMessage(from: decoder))
		case "set_image_ack":
			self = try .setImageAck(SetImageAckMessage(from: decoder))
		case "status":
			self = try .status(StatusMessage(from: decoder))
		case "queue_position":
			self = try .queuePosition(QueuePositionMessage(from: decoder))
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
		case .offer(let msg):
			try msg.encode(to: encoder)
		case .answer(let msg):
			try msg.encode(to: encoder)
		case .iceCandidate(let msg):
			try msg.encode(to: encoder)
		case .error(let msg):
			try msg.encode(to: encoder)
		case .sessionId(let msg):
			try msg.encode(to: encoder)
		case .generationStarted(let msg):
			try msg.encode(to: encoder)
		case .generationTick(let msg):
			try msg.encode(to: encoder)
		case .generationEnded(let msg):
			try msg.encode(to: encoder)
		case .promptAck(let msg):
			try msg.encode(to: encoder)
		case .setImageAck(let msg):
			try msg.encode(to: encoder)
		case .status(let msg):
			try msg.encode(to: encoder)
		case .queuePosition(let msg):
			try msg.encode(to: encoder)
		}
	}

	private enum CodingKeys: String, CodingKey {
		case type
	}
}

enum OutgoingWebSocketMessage: Encodable, Sendable {
	case offer(OfferMessage)
	case answer(AnswerMessage)
	case iceCandidate(IceCandidateMessage)
	case prompt(PromptMessage)
	case setImage(SetImageMessage)

	func encode(to encoder: Encoder) throws {
		switch self {
		case .offer(let msg):
			try msg.encode(to: encoder)
		case .answer(let msg):
			try msg.encode(to: encoder)
		case .iceCandidate(let msg):
			try msg.encode(to: encoder)
		case .prompt(let msg):
			try msg.encode(to: encoder)
		case .setImage(let msg):
			try msg.encode(to: encoder)
		}
	}
}
