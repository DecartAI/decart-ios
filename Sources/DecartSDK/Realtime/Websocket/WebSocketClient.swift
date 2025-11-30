import Foundation

actor WebSocketClient {
	var isConnected: Bool = false

	private let stream: SocketStream
	private var listeningTask: Task<Void, Never>?
	private let decoder = JSONDecoder()
	private let encoder = JSONEncoder()

	private let eventStreamContinuation: AsyncStream<IncomingWebSocketMessage>.Continuation
	nonisolated let websocketEventStream: AsyncStream<IncomingWebSocketMessage>

	init(url: URL) async {
		let (websocketEventStream, eventStreamContinuation) = AsyncStream.makeStream(of: IncomingWebSocketMessage.self)
		self.eventStreamContinuation = eventStreamContinuation
		self.websocketEventStream = websocketEventStream
		let socketConnection = URLSession.shared.webSocketTask(with: url)
		stream = SocketStream(task: socketConnection)
		mountListener()
	}

	private func mountListener() {
		listeningTask = Task { [weak self] in
			guard let self else { return }
			do {
				for try await msg in self.stream {
					if Task.isCancelled { return }
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
				self.eventStreamContinuation.finish()
			}
		}
	}

	private func handleIncomingMessage(_ text: String) async {
		guard let data = text.data(using: .utf8) else { return }
		guard let message = try? decoder.decode(IncomingWebSocketMessage.self, from: data) else { return }
		eventStreamContinuation.yield(message)
	}

	func send<T: Codable>(_ message: T) throws {
		let data = try encoder.encode(message)
		guard let jsonString = String(data: data, encoding: .utf8) else {
			throw DecartError.websocketError("unable to encode message")
		}
		Task { [stream] in try await stream.sendMessage(.string(jsonString)) }
	}

	deinit {
		listeningTask?.cancel()
		eventStreamContinuation.finish()
		stream.cancel()
	}
}
