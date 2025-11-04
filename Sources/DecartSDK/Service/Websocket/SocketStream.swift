//
//  SocketStream.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 03/11/2025.
//
import Foundation

typealias WebSocketStream = AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>

extension URLSessionWebSocketTask {
	var stream: WebSocketStream {
		return WebSocketStream { continuation in
			Task {
				var isAlive = true
				while isAlive && closeCode == .invalid {
					do {
						let value = try await receive()
						continuation.yield(value)
					} catch {
						continuation.finish(throwing: error)
						isAlive = false
					}
				}
			}
		}
	}
}

class SocketStream: AsyncSequence {
	typealias AsyncIterator = WebSocketStream.Iterator
	typealias Element = URLSessionWebSocketTask.Message

	private var continuation: WebSocketStream.Continuation?
	private let task: URLSessionWebSocketTask

	private lazy var stream: WebSocketStream = WebSocketStream { continuation in
		self.continuation = continuation
		waitForNextValue()
	}

	init(task: URLSessionWebSocketTask) {
		self.task = task
		task.resume()
	}

	private func waitForNextValue() {
		guard task.closeCode == .invalid else {
			continuation?.finish()
			return
		}
		task.receive(completionHandler: { [weak self] result in
			guard let continuation = self?.continuation else {
				return
			}
			do {
				let message = try result.get()
				continuation.yield(message)
				self?.waitForNextValue()
			} catch {
				continuation.finish(throwing: error)
			}
		})
	}

	deinit {
		cancel()
		continuation?.finish()
	}

	func sendMessage(_ message: URLSessionWebSocketTask.Message) async throws {
		try await task.send(message)
	}

	func makeAsyncIterator() -> AsyncIterator {
		return stream.makeAsyncIterator()
	}

	func cancel() {
		task.cancel(with: .goingAway, reason: nil)
		continuation?.finish()
	}
}
