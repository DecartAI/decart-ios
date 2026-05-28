import XCTest
@testable import DecartSDK

final class AsyncRequestTests: XCTestCase {

	// MARK: - fulfill

	func testFulfillResolvesPendingWaiter() async throws {
		let request = AsyncRequest<String>()

		async let value = request.wait(
			timeout: 5,
			timeoutError: DecartError.websocketError("timed out")
		)
		await waitForRegistration()

		request.fulfill("hello")

		let result = try await value
		XCTAssertEqual(result, "hello")
	}

	func testFulfillBeforeWaitDeliversBufferedValue() async throws {
		let request = AsyncRequest<Int>()

		request.fulfill(42)

		let result = try await request.wait(
			timeout: 5,
			timeoutError: DecartError.websocketError("timed out")
		)
		XCTAssertEqual(result, 42)
	}

	// MARK: - fail

	func testFailDeliversErrorToPendingWaiter() async throws {
		let request = AsyncRequest<String>()

		async let value = request.wait(
			timeout: 5,
			timeoutError: DecartError.websocketError("timed out")
		)
		await waitForRegistration()

		request.fail(DecartError.serverError("rejected"))

		do {
			_ = try await value
			XCTFail("expected throw")
		} catch let DecartError.serverError(message) {
			XCTAssertEqual(message, "rejected")
		} catch {
			XCTFail("expected DecartError.serverError, got \(error)")
		}
	}

	func testFailBeforeWaitDeliversBufferedError() async throws {
		let request = AsyncRequest<String>()

		request.fail(DecartError.serverError("rejected"))

		do {
			_ = try await request.wait(
				timeout: 5,
				timeoutError: DecartError.websocketError("timed out")
			)
			XCTFail("expected throw")
		} catch let DecartError.serverError(message) {
			XCTAssertEqual(message, "rejected")
		} catch {
			XCTFail("expected DecartError.serverError, got \(error)")
		}
	}

	// MARK: - timeout

	func testTimeoutThrowsConfiguredError() async throws {
		let request = AsyncRequest<String>()

		do {
			_ = try await request.wait(
				timeout: 0.1,
				timeoutError: DecartError.websocketError("Prompt acknowledgment timed out")
			)
			XCTFail("expected timeout")
		} catch let DecartError.websocketError(message) {
			XCTAssertEqual(message, "Prompt acknowledgment timed out")
		} catch {
			XCTFail("expected websocketError(timeout), got \(error)")
		}
	}

	// MARK: - reset

	func testResetCancelsPendingWaiter() async throws {
		let request = AsyncRequest<String>()

		async let value = request.wait(
			timeout: 5,
			timeoutError: DecartError.websocketError("timed out")
		)
		await waitForRegistration()

		request.reset()

		do {
			_ = try await value
			XCTFail("expected cancellation")
		} catch is CancellationError {
			// expected
		} catch {
			XCTFail("expected CancellationError, got \(error)")
		}
	}

	func testResetClearsBufferedValue() async throws {
		let request = AsyncRequest<String>()

		request.fulfill("stale")
		request.reset()

		do {
			_ = try await request.wait(
				timeout: 0.1,
				timeoutError: DecartError.websocketError("timed out after reset")
			)
			XCTFail("expected timeout after reset")
		} catch let DecartError.websocketError(message) {
			XCTAssertEqual(message, "timed out after reset")
		} catch {
			XCTFail("expected websocketError(timeout), got \(error)")
		}
	}

	// MARK: - subsequent use

	func testSecondWaitAfterFulfillIsIndependent() async throws {
		let request = AsyncRequest<String>()

		async let firstValue = request.wait(
			timeout: 5,
			timeoutError: DecartError.websocketError("timed out")
		)
		await waitForRegistration()
		request.fulfill("one")
		let firstResult = try await firstValue
		XCTAssertEqual(firstResult, "one")

		async let secondValue = request.wait(
			timeout: 5,
			timeoutError: DecartError.websocketError("timed out")
		)
		await waitForRegistration()
		request.fulfill("two")
		let secondResult = try await secondValue
		XCTAssertEqual(secondResult, "two")
	}

	// MARK: - PromptAck / SetImageAck payload round-trip

	func testAsyncRequestCarriesPromptAckPayload() async throws {
		let request = AsyncRequest<PromptAckMessage>()

		async let value = request.wait(
			timeout: 5,
			timeoutError: DecartError.websocketError("timed out")
		)
		await waitForRegistration()

		request.fulfill(PromptAckMessage(
			type: "prompt_ack",
			prompt: "a cyberpunk cityscape",
			success: true,
			error: nil
		))

		let ack = try await value
		XCTAssertEqual(ack.prompt, "a cyberpunk cityscape")
		XCTAssertEqual(ack.success, true)
	}

	func testAsyncRequestCarriesSetImageAckPayload() async throws {
		let request = AsyncRequest<SetImageAckMessage>()

		async let value = request.wait(
			timeout: 5,
			timeoutError: DecartError.websocketError("timed out")
		)
		await waitForRegistration()

		request.fulfill(SetImageAckMessage(
			type: "set_image_ack",
			success: false,
			error: "image too large"
		))

		let ack = try await value
		XCTAssertEqual(ack.success, false)
		XCTAssertEqual(ack.error, "image too large")
	}

	// MARK: - Helpers

	private func waitForRegistration() async {
		for _ in 0..<10 { await Task.yield() }
		try? await Task.sleep(nanoseconds: 50_000_000)
	}
}
