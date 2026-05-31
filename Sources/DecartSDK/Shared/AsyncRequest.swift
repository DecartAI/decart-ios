import Foundation

final class AsyncRequest<Value: Sendable>: @unchecked Sendable {
	private struct Waiter {
		let id: UUID
		let continuation: CheckedContinuation<Value, Error>
		let timeoutTask: Task<Void, Never>
	}

	private let lock = NSLock()
	private var waiter: Waiter?
	private var bufferedResult: Result<Value, Error>?

	func fulfill(_ value: Value) {
		resume(.success(value))
	}

	func fail(_ error: Error) {
		resume(.failure(error))
	}

	func reset() {
		let pending: Waiter?
		lock.lock()
		bufferedResult = nil
		pending = waiter
		waiter = nil
		lock.unlock()

		pending?.timeoutTask.cancel()
		pending?.continuation.resume(throwing: CancellationError())
	}

	func wait(
		timeout: TimeInterval,
		timeoutError: @Sendable @autoclosure () -> Error
	) async throws -> Value {
		let id = UUID()
		let timeoutErr = timeoutError()
		let timeoutNs = UInt64(max(timeout, 0) * 1_000_000_000)

		return try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { continuation in
				let timeoutTask = Task { [weak self] in
					try? await Task.sleep(nanoseconds: timeoutNs)
					guard !Task.isCancelled else { return }
					self?.completeWaiter(id: id, result: .failure(timeoutErr))
				}

				let buffered: Result<Value, Error>?
				let replaced: Waiter?
				lock.lock()
				buffered = bufferedResult
				bufferedResult = nil
				if buffered == nil {
					replaced = waiter
					waiter = Waiter(id: id, continuation: continuation, timeoutTask: timeoutTask)
				} else {
					replaced = nil
				}
				lock.unlock()

				if let buffered {
					timeoutTask.cancel()
					continuation.resume(with: buffered)
				}

				if let replaced {
					replaced.timeoutTask.cancel()
					replaced.continuation.resume(throwing: CancellationError())
				}
			}
		} onCancel: {
			completeWaiter(id: id, result: .failure(CancellationError()))
		}
	}

	private func resume(_ result: Result<Value, Error>) {
		let pending: Waiter?
		lock.lock()
		if let activeWaiter = waiter {
			pending = activeWaiter
			waiter = nil
		} else {
			pending = nil
			bufferedResult = result
		}
		lock.unlock()

		pending?.timeoutTask.cancel()
		pending?.continuation.resume(with: result)
	}

	private func completeWaiter(id: UUID, result: Result<Value, Error>) {
		let pending: Waiter?
		lock.lock()
		if waiter?.id == id {
			pending = waiter
			waiter = nil
		} else {
			pending = nil
		}
		lock.unlock()

		pending?.timeoutTask.cancel()
		pending?.continuation.resume(with: result)
	}
}
