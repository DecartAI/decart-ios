//
//  WebSocketService.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 03/11/2025.
//

import Foundation
import Observation

actor WebSocketService {
	var isConnected: Bool = false
	var socketError: DecartError?

	private var stream: SocketStream?
	private var listeningTask: Task<Void, Never>?
	private let decoder = JSONDecoder()
	private let encoder = JSONEncoder()

	private var eventStreamContinuation: AsyncStream<IncomingWebSocketMessage>.Continuation
	let websocketEventStream: AsyncStream<IncomingWebSocketMessage>

	init() {
		let (websocketEventStream, eventStreamContinuation) = AsyncStream.makeStream(of: IncomingWebSocketMessage.self)
		self.eventStreamContinuation = eventStreamContinuation
		self.websocketEventStream = websocketEventStream
	}

	func connect(url: URL) {
		if stream != nil { return }
		let socketConnection = URLSession.shared.webSocketTask(with: url)
		stream = SocketStream(task: socketConnection)

		listeningTask = Task { [weak self] in
			guard let self = self, let stream = await self.stream else {
				return
			}
			do {
				for try await msg in stream {
					switch msg {
					case .string(let text):
						await self.handleIncomingMessage(text)
					case .data(let d):
						if let text = String(data: d, encoding: .utf8) {
							await self.handleIncomingMessage(text)
						}
					@unknown default: break
					}
				}
			} catch {
				DecartLogger
					.log("error in ws listening loop: \(error)", level: .error)
				await self.eventStreamContinuation.finish()
			}
		}
	}

	private func handleIncomingMessage(_ text: String) async {
		guard let data = text.data(using: .utf8) else { return }
		do {
			let message = try decoder.decode(IncomingWebSocketMessage.self, from: data)
			eventStreamContinuation.yield(message)
		} catch {
			DecartLogger
				.log("error while handling incoming message: \(error)", level: .error)
			eventStreamContinuation.finish()
		}
	}

	func send<T: Codable>(_ message: T) throws {
		guard let stream = stream else {
			DecartLogger.log("tried to send ws message when its closed", level: .warning)
			return
		}

		let data = try encoder.encode(message)
		guard let jsonString = String(data: data, encoding: .utf8) else {
			DecartLogger.log("unable to encode message", level: .warning)
			throw DecartError.websocketError("unable to encode message")
		}
		Task { [stream] in
			try await stream.sendMessage(.string(jsonString))
		}
	}

	func disconnect() async {
		DecartLogger.log("disconnecting from websocket", level: .info)
		eventStreamContinuation.finish()
		listeningTask?.cancel()
		listeningTask = nil
		stream?.cancel()
		stream = nil
		isConnected = false
	}

	deinit { DecartLogger.log("Websocket Service deinit", level: .info) }
}
