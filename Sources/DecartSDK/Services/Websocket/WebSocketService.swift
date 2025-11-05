//
//  WebSocketService.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 03/11/2025.
//

import Foundation
import Observation

protocol WebSocketMessageHandler<Message>: AnyObject where Message: Decodable {
	associatedtype Message
	func handle(_ message: Message) async
}

class WebSocketService {
	var isConnected: Bool = false
	var socketError: DecartError?

	weak var messageHandler: WebSocketMessageHandler<IncomingWebSocketMessage>?

	private var stream: SocketStream?
	private var listeningTask: Task<Void, Never>?
	private let decoder = JSONDecoder()
	private let encoder = JSONEncoder()

	func connect(url: URL) {
		if isConnected { return }

		let socketConnection = URLSession.shared.webSocketTask(with: url)
		stream = SocketStream(task: socketConnection)
		isConnected = true

		listeningTask = Task {
			await listenForMessages()
		}
	}

	private func listenForMessages() async {
		guard let stream = stream else { return }

		do {
			DecartLogger.log("WS connected!", level: .info)
			for try await message in stream {
				switch message {
				case .string(let text):
					await handleIncomingMessage(text)
				case .data(let data):
					if let text = String(data: data, encoding: .utf8) {
						await handleIncomingMessage(text)
					}
				@unknown default:
					break
				}
			}
		} catch {
			DecartLogger.log(error.localizedDescription, level: .error)
			socketError = DecartError.websocketError(error.localizedDescription)
		}
	}

	private func handleIncomingMessage(_ text: String) async {
		guard let data = text.data(using: .utf8) else { return }

		do {
			let message = try decoder.decode(
				IncomingWebSocketMessage.self,
				from: data
			)

			await messageHandler?.handle(message)
		} catch {
			DecartLogger.log("unable to decode message", level: .warning)
			socketError = DecartError.websocketError("unable to decode message")
		}
	}

	func send<T: Codable>(_ message: T) async throws {
		guard let stream = stream else {
			DecartLogger.log("tried to send ws message when its closed", level: .warning)
			return
		}

		let data = try encoder.encode(message)
		guard let jsonString = String(data: data, encoding: .utf8) else {
			DecartLogger.log("unable to encode message", level: .warning)
			throw DecartError.websocketError("unable to encode message")
		}

		try await stream.sendMessage(.string(jsonString))
	}

	func disconnect() async {
		DecartLogger.log("disconnecting from websocket", level: .info)
		listeningTask?.cancel()
		listeningTask = nil
		stream?.cancel()
		stream = nil
		isConnected = false
	}

	deinit { DecartLogger.log("Websocket Service deinit", level: .info) }
}
