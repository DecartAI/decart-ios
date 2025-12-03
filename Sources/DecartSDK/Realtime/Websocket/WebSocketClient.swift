import Foundation
import WebSocket

final class WebSocketClient: Sendable {
//	var isConnected: Bool = false

	private let socket: WebSocket?
	private nonisolated(unsafe) var listeningTask: Task<Void, Never>?
	private let decoder = JSONDecoder()
	private let encoder = JSONEncoder()

	private let eventStreamContinuation: AsyncStream<IncomingWebSocketMessage>.Continuation
	nonisolated let websocketEventStream: AsyncStream<IncomingWebSocketMessage>

	init(url: URL) async {
		let (websocketEventStream, eventStreamContinuation) = AsyncStream.makeStream(of: IncomingWebSocketMessage.self)
		self.eventStreamContinuation = eventStreamContinuation
		self.websocketEventStream = websocketEventStream
		let newSocket = try? await WebSocket.system(url: url)
		socket = newSocket
		try? await newSocket?.open()
		mountListener()
	}

	private func mountListener() {
		listeningTask = Task { [weak self] in
			guard let self else { return }
			do {
				guard let socket = self.socket else { return }
				for try await msg in socket.messages {
					if Task.isCancelled { return }
					switch msg {
					case .text(let text):
						self.handleIncomingMessage(text)
					case .data(let d):
						if let text = String(data: d, encoding: .utf8) {
							self.handleIncomingMessage(text)
						}
					@unknown default: break
					}
				}
			} catch {
				self.eventStreamContinuation.finish()
			}
		}
	}

	private func handleIncomingMessage(_ text: String) {
		guard let data = text.data(using: .utf8) else { return }

		do {
			let message = try decoder.decode(IncomingWebSocketMessage.self, from: data)
			eventStreamContinuation.yield(message)
		} catch {
			DecartLogger.log(
				"unable to decode websocket message: \(error)",
				level: .warning
			)
		}
	}

	func send<T: Encodable & Sendable>(_ message: T) async throws {
		let data = try encoder.encode(message)
		guard let jsonString = String(data: data, encoding: .utf8) else { return }
		guard let socket else { return }
		try await socket.send(.text(jsonString))
	}

	func disconnect() {
		Task { [socket] in
			if let socket {
				try? await socket.close()
			}
		}
	}

	deinit {
		listeningTask?.cancel()
		eventStreamContinuation.finish()
		disconnect()
	}
}
