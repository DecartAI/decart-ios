//
//  SignalingModel.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 03/11/2025.
//

import Foundation
import WebRTC

struct InitializeConnectionMessage: Codable {
	let type: String
	let apiKey: String
	let model: String

	let initialPrompt: String?
	
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

	init(candidate: RTCIceCandidate) {
		guard let sdpMid = candidate.sdpMid else {
			DecartLogger.log("found invalid candidate without sdpMid", level: .warning)
			fatalError(
				"found invalid candidate without sdpMid. This should never happen."
			)
		}

		self.type = "ice-candidate"
		self.candidate = IceCandidatePayload(
			candidate: candidate.sdp,
			sdpMLineIndex: candidate.sdpMLineIndex,
			sdpMid: sdpMid
		)
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

enum IncomingWebSocketMessage: Codable {
	case offer(OfferMessage)
	case answer(AnswerMessage)
	case iceCandidate(IceCandidateMessage)

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let type = try container.decode(String.self, forKey: .type)
		DecartLogger.log("got incoming message \(type)", level: .info)

		switch type {
		case "offer":
			self = try .offer(OfferMessage(from: decoder))
		case "answer":
			self = try .answer(AnswerMessage(from: decoder))
		case "ice-candidate":
			self = try .iceCandidate(IceCandidateMessage(from: decoder))
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
		}
	}

	private enum CodingKeys: String, CodingKey {
		case type
	}
}

enum OutgoingWebSocketMessage: Codable {
	case offer(OfferMessage)
	case answer(AnswerMessage)
	case iceCandidate(IceCandidateMessage)
	case prompt(PromptMessage)
	case switchCamera(SwitchCameraMessage)

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
		case .switchCamera(let msg):
			try msg.encode(to: encoder)
		}
	}
}
