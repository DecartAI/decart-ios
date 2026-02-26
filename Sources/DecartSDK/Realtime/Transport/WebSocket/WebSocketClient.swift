import Foundation
import WebSocket

actor WebSocketClient {
	private var socket: WebSocket?
	private var listeningTask: Task<Void, Never>?
	private let decoder = JSONDecoder()
	private let encoder = JSONEncoder()

	private let eventStreamContinuation: AsyncStream<IncomingWebSocketMessage>.Continuation
	nonisolated let websocketEventStream: AsyncStream<IncomingWebSocketMessage>

	init(url: URL) async {
		let (websocketEventStream, eventStreamContinuation) =
			AsyncStream.makeStream(of: IncomingWebSocketMessage.self)
		self.eventStreamContinuation = eventStreamContinuation
		self.websocketEventStream = websocketEventStream

		do {
			let newSocket = try await WebSocket.system(url: url)
			socket = newSocket
			try await newSocket.open()
			mountListener(socket: newSocket)
		} catch {
			socket = nil
			eventStreamContinuation.finish()
			DecartLogger.log(
				"unable to open websocket: \(error)",
				level: .error
			)
		}
	}

	private func mountListener(socket: WebSocket) {
		listeningTask?.cancel()
		listeningTask = Task { [weak self] in
			guard let self else { return }
			for await msg in socket.messages {
				if Task.isCancelled { return }
				await self.handleIncomingMessage(msg)
			}
			await self.finishStream()
		}
	}

	private func handleIncomingMessage(_ message: WebSocketMessage) {
		guard
			let text = message.stringValue,
			let data = text.data(using: .utf8)
		else { return }

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

	private func finishStream() {
		eventStreamContinuation.finish()
	}

	func send<T: Encodable & Sendable>(_ message: T) async throws {
		let data = try encoder.encode(message)
		guard let jsonString = String(data: data, encoding: .utf8) else { return }
		guard let socket else { return }
		try await socket.send(.text(jsonString))
	}

	func disconnect() async {
		listeningTask?.cancel()
		listeningTask = nil
		eventStreamContinuation.finish()
		guard let socket else { return }
		try? await socket.close()
	}
}
