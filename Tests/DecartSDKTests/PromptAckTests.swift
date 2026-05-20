import XCTest
@testable import DecartSDK

final class PromptAckTests: XCTestCase {

	// MARK: - Helpers

	private func makeManager(hasReferenceImage: Bool = false) -> DecartRealtimeManager {
		let model = ModelDefinition(
			name: "test-model",
			urlPath: "/v1/test",
			fps: 24,
			width: 512,
			height: 512,
			hasReferenceImage: hasReferenceImage
		)
		return DecartRealtimeManager(
			signalingServerURL: URL(string: "wss://example.test")!,
			options: RealtimeConfiguration(model: model)
		)
	}

	// MARK: - prompt_ack

	func testPromptAckMatchingPromptTextResolvesWaiter() async throws {
		let manager = makeManager()
		let promptText = "a cyberpunk cityscape"

		async let wait: Void = manager.test_awaitRuntimePromptAck(prompt: promptText, timeout: 5)
		await waitForRegistration()

		manager.test_recordPromptAck(PromptAckMessage(
			type: "prompt_ack",
			prompt: promptText,
			success: true,
			error: nil
		))
		try await wait // succeeds
	}

	func testPromptAckFailureThrowsServerError() async throws {
		let manager = makeManager()
		let promptText = "a forbidden prompt"

		async let wait: Void = manager.test_awaitRuntimePromptAck(prompt: promptText, timeout: 5)
		await waitForRegistration()

		manager.test_recordPromptAck(PromptAckMessage(
			type: "prompt_ack",
			prompt: promptText,
			success: false,
			error: "moderation rejected"
		))

		do {
			try await wait
			XCTFail("expected throw")
		} catch let DecartError.serverError(message) {
			XCTAssertEqual(message, "moderation rejected")
		} catch {
			XCTFail("expected DecartError.serverError, got \(error)")
		}
	}

	func testPromptAckFailureWithoutErrorMessageUsesDefault() async throws {
		let manager = makeManager()
		let promptText = "a prompt"

		async let wait: Void = manager.test_awaitRuntimePromptAck(prompt: promptText, timeout: 5)
		await waitForRegistration()

		manager.test_recordPromptAck(PromptAckMessage(
			type: "prompt_ack",
			prompt: promptText,
			success: false,
			error: nil
		))

		do {
			try await wait
			XCTFail("expected throw")
		} catch let DecartError.serverError(message) {
			XCTAssertEqual(message, "Failed to send prompt")
		} catch {
			XCTFail("expected DecartError.serverError, got \(error)")
		}
	}

	func testNonMatchingPromptAckIsIgnored() async throws {
		let manager = makeManager()
		let target = "match-me"

		async let wait: Void = manager.test_awaitRuntimePromptAck(prompt: target, timeout: 5)
		await waitForRegistration()

		manager.test_recordPromptAck(PromptAckMessage(
			type: "prompt_ack",
			prompt: "other",
			success: true,
			error: nil
		))

		manager.test_recordPromptAck(PromptAckMessage(
			type: "prompt_ack",
			prompt: target,
			success: true,
			error: nil
		))
		try await wait
	}

	func testPromptAckTimeoutThrows() async throws {
		let manager = makeManager()
		let promptText = "slow prompt"

		do {
			try await manager.test_awaitRuntimePromptAck(prompt: promptText, timeout: 0.1)
			XCTFail("expected timeout")
		} catch let DecartError.websocketError(message) {
			XCTAssertEqual(message, "Prompt acknowledgment timed out")
		} catch {
			XCTFail("expected DecartError.websocketError(timeout), got \(error)")
		}
	}

	func testFailAllPendingRuntimeWaitersFailsPromptWaiter() async throws {
		let manager = makeManager()
		let promptText = "a prompt"

		async let wait: Void = manager.test_awaitRuntimePromptAck(prompt: promptText, timeout: 5)
		await waitForRegistration()

		manager.test_failAllPendingRuntimeWaiters(
			DecartError.websocketError("WebSocket disconnected")
		)

		do {
			try await wait
			XCTFail("expected throw on disconnect")
		} catch let DecartError.websocketError(message) {
			XCTAssertEqual(message, "WebSocket disconnected")
		} catch {
			XCTFail("expected websocket disconnect error, got \(error)")
		}
	}

	// MARK: - set_image_ack

	func testSetImageAckSuccessResolvesWaiter() async throws {
		let manager = makeManager()

		async let wait: Void = manager.test_awaitRuntimeSetImageAck(timeout: 5)
		await waitForRegistration()

		manager.test_recordSetImageAck(SetImageAckMessage(
			type: "set_image_ack",
			success: true,
			error: nil
		))
		try await wait
	}

	func testSetImageAckFailureThrowsServerError() async throws {
		let manager = makeManager()

		async let wait: Void = manager.test_awaitRuntimeSetImageAck(timeout: 5)
		await waitForRegistration()

		manager.test_recordSetImageAck(SetImageAckMessage(
			type: "set_image_ack",
			success: false,
			error: "image too large"
		))

		do {
			try await wait
			XCTFail("expected throw")
		} catch let DecartError.serverError(message) {
			XCTAssertEqual(message, "image too large")
		} catch {
			XCTFail("expected DecartError.serverError, got \(error)")
		}
	}

	func testSetImageAckTimeoutThrows() async throws {
		let manager = makeManager()

		do {
			try await manager.test_awaitRuntimeSetImageAck(timeout: 0.1)
			XCTFail("expected timeout")
		} catch let DecartError.websocketError(message) {
			XCTAssertEqual(message, "Image send timed out")
		} catch {
			XCTFail("expected timeout, got \(error)")
		}
	}

	func testSetImageAckSingleFlightSupersedesPriorWaiter() async throws {
		let manager = makeManager()

		let first: Task<Void, Error> = Task {
			try await manager.test_awaitRuntimeSetImageAck(timeout: 5)
		}
		await waitForRegistration()

		// Second call supersedes the first.
		let second: Task<Void, Error> = Task {
			try await manager.test_awaitRuntimeSetImageAck(timeout: 5)
		}
		await waitForRegistration()

		// First should now be failed with "superseded".
		do {
			try await first.value
			XCTFail("expected first call to be superseded")
		} catch let DecartError.serverError(message) {
			XCTAssertEqual(message, "superseded")
		} catch {
			XCTFail("expected serverError(superseded), got \(error)")
		}

		// Second resolves normally on ack.
		manager.test_recordSetImageAck(SetImageAckMessage(
			type: "set_image_ack",
			success: true,
			error: nil
		))
		try await second.value
	}

	func testFailAllPendingRuntimeWaitersFailsSetImageWaiter() async throws {
		let manager = makeManager()

		async let wait: Void = manager.test_awaitRuntimeSetImageAck(timeout: 5)
		await waitForRegistration()

		manager.test_failAllPendingRuntimeWaiters(
			DecartError.serverError("server fault")
		)

		do {
			try await wait
			XCTFail("expected throw")
		} catch let DecartError.serverError(message) {
			XCTAssertEqual(message, "server fault")
		} catch {
			XCTFail("expected serverError(server fault), got \(error)")
		}
	}

	// MARK: - Concurrent prompt waiters

	func testMultiplePromptWaitersAreIndependent() async throws {
		let manager = makeManager()

		let first: Task<Void, Error> = Task {
			try await manager.test_awaitRuntimePromptAck(prompt: "first", timeout: 5)
		}
		let second: Task<Void, Error> = Task {
			try await manager.test_awaitRuntimePromptAck(prompt: "second", timeout: 5)
		}
		await waitForRegistration()

		// Resolve "second" first; "first" must remain pending.
		manager.test_recordPromptAck(PromptAckMessage(
			type: "prompt_ack",
			prompt: "second",
			success: true,
			error: nil
		))
		try await second.value

		// "first" still pending — resolve it now.
		manager.test_recordPromptAck(PromptAckMessage(
			type: "prompt_ack",
			prompt: "first",
			success: true,
			error: nil
		))
		try await first.value
	}

	// MARK: - Helpers

	// Waits long enough for an `async let` / `Task` waiter to actually land
	// in the manager's dict before the test delivers an ack.
	private func waitForRegistration() async {
		for _ in 0..<10 { await Task.yield() }
		try? await Task.sleep(nanoseconds: 50_000_000)
	}
}
