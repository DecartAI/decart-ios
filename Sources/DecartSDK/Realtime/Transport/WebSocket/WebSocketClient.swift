import Foundation
import WebSocket

actor WebSocketClient {
	private var socket: WebSocket?
	private var listeningTask: Task<Void, Never>?
	private let decoder = JSONDecoder()
	private let encoder = JSONEncoder()

	private let eventStreamContinuation: AsyncStream<IncomingWebSocketMessage>.Continuation
	nonisolated let websocketEventStream: AsyncStream<IncomingWebSocketMessage>

	init(url: URL, timeout: TimeInterval) async throws {
		let (websocketEventStream, eventStreamContinuation) =
			AsyncStream.makeStream(of: IncomingWebSocketMessage.self)
		self.eventStreamContinuation = eventStreamContinuation
		self.websocketEventStream = websocketEventStream

		let newSocket = try await withThrowingTaskGroup(of: WebSocket.self) { group in
			group.addTask {
				let socket = try await WebSocket.system(url: url)
				try await socket.open()
				return socket
			}
			group.addTask {
				try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
				throw DecartError.websocketError("WebSocket open timeout")
			}

			guard let socket = try await group.next() else {
				throw DecartError.websocketError("WebSocket open failed")
			}
			group.cancelAll()
			return socket
		}
		self.socket = newSocket
		mountListener(socket: newSocket)
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
		guard let jsonString = String(data: data, encoding: .utf8) else {
			throw DecartError.websocketError("Failed to encode websocket message")
		}
		guard let socket else {
			throw DecartError.websocketError("WebSocket not connected")
		}
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
