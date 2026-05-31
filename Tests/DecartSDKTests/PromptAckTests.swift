import XCTest
@testable import DecartSDK

final class PromptAckTests: XCTestCase {
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

	func testPromptAckMatchingPromptTextResolvesWaiter() async throws {
		let manager = makeManager()
		let promptText = "a cyberpunk cityscape"

		async let wait: Void = manager.test_awaitRuntimePromptAck(prompt: promptText, timeout: 5)
		await waitForRegistration()

		await manager.test_recordPromptAck(PromptAckMessage(
			type: "prompt_ack",
			prompt: promptText,
			success: true,
			error: nil
		))
		try await wait
	}

	func testPromptAckFailureThrowsServerError() async throws {
		let manager = makeManager()
		let promptText = "a forbidden prompt"

		async let wait: Void = manager.test_awaitRuntimePromptAck(prompt: promptText, timeout: 5)
		await waitForRegistration()

		await manager.test_recordPromptAck(PromptAckMessage(
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

	func testNonMatchingPromptAckIsIgnored() async throws {
		let manager = makeManager()
		let target = "match-me"

		async let wait: Void = manager.test_awaitRuntimePromptAck(prompt: target, timeout: 5)
		await waitForRegistration()

		await manager.test_recordPromptAck(PromptAckMessage(
			type: "prompt_ack",
			prompt: "other",
			success: true,
			error: nil
		))

		await manager.test_recordPromptAck(PromptAckMessage(
			type: "prompt_ack",
			prompt: target,
			success: true,
			error: nil
		))
		try await wait
	}

	func testMultiplePromptWaitersAreIndependent() async throws {
		let manager = makeManager()

		async let first: Void = manager.test_awaitRuntimePromptAck(prompt: "first", timeout: 5)
		async let second: Void = manager.test_awaitRuntimePromptAck(prompt: "second", timeout: 5)
		await waitForRegistration()

		await manager.test_recordPromptAck(PromptAckMessage(
			type: "prompt_ack",
			prompt: "second",
			success: true,
			error: nil
		))
		try await second

		await manager.test_recordPromptAck(PromptAckMessage(
			type: "prompt_ack",
			prompt: "first",
			success: true,
			error: nil
		))
		try await first
	}

	func testPromptAckTimeoutThrows() async throws {
		let manager = makeManager()

		do {
			try await manager.test_awaitRuntimePromptAck(prompt: "slow prompt", timeout: 0.1)
			XCTFail("expected timeout")
		} catch let DecartError.websocketError(message) {
			XCTAssertEqual(message, "Prompt acknowledgment timed out")
		} catch {
			XCTFail("expected DecartError.websocketError(timeout), got \(error)")
		}
	}

	func testFailAllPendingRuntimeWaitersFailsPromptWaiter() async throws {
		let manager = makeManager()

		async let wait: Void = manager.test_awaitRuntimePromptAck(prompt: "a prompt", timeout: 5)
		await waitForRegistration()

		await manager.test_failAllPendingRuntimeWaiters(
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

	private func waitForRegistration() async {
		for _ in 0..<10 { await Task.yield() }
		try? await Task.sleep(nanoseconds: 50_000_000)
	}
}
