import Foundation

final class AsyncRequest<Value: Sendable>: @unchecked Sendable {
	private var continuation: CheckedContinuation<Value, Error>?
	private var bufferedResult: Result<Value, Error>?

	func fulfill(_ value: Value) {
		resume(.success(value))
	}

	func fail(_ error: Error) {
		resume(.failure(error))
	}

	func reset() {
		bufferedResult = nil
		if let pending = continuation {
			continuation = nil
			pending.resume(throwing: CancellationError())
		}
	}

	func wait(
		timeout: TimeInterval,
		timeoutError: @Sendable @autoclosure () -> Error
	) async throws -> Value {
		if let buffered = bufferedResult {
			bufferedResult = nil
			return try buffered.get()
		}

		let timeoutNs = UInt64(timeout * 1_000_000_000)
		let timeoutErr = timeoutError()

		do {
			return try await withThrowingTaskGroup(of: Value.self) { group in
				group.addTask {
					try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Value, Error>) in
						self.continuation = cont
					}
				}
				group.addTask { [timeoutErr] in
					try await Task.sleep(nanoseconds: timeoutNs)
					throw timeoutErr
				}
				defer { group.cancelAll() }
				return try await group.next()!
			}
		} catch {
			if let pending = continuation {
				continuation = nil
				pending.resume(throwing: error)
			}
			throw error
		}
	}

	private func resume(_ result: Result<Value, Error>) {
		if let pending = continuation {
			continuation = nil
			pending.resume(with: result)
		} else {
			bufferedResult = result
		}
	}
}
