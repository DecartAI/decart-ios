import XCTest
@testable import DecartSDK

/// Ports `connection-quality.unit.test.ts` from the JS SDK. The pure
/// `QualitySignals` seam stands in for the JS `WebRTCStats` fixture; on iOS the
/// LiveKit → `QualitySignals` extraction is integration-tested, not unit-tested.
///
/// Note: `fractionLost` here is a normalized 0–1 fraction (the value LiveKit
/// reports on Apple platforms), so unlike the JS test there is no ×256/÷256 step.
final class ConnectionQualityTests: XCTestCase {
	private let thresholds = ConnectionQualityThresholds.default

	/// Builds a signal set that scores "good" by default; override per test.
	private func makeSignals(
		rttMs: Double? = 50,
		g2gMs: Double? = nil,
		g2gDropRatio: Double? = nil,
		fractionLost: Double? = 0,
		availableOutgoingKbps: Double? = 4000,
		fps: Double? = 30,
		freezeCountDelta: Int? = 0,
		qualityLimitationReason: String? = "none",
		isRelayed: Bool = false
	) -> QualitySignals {
		QualitySignals(
			rttMs: rttMs,
			g2gMs: g2gMs,
			fractionLost: fractionLost,
			g2gDropRatio: g2gDropRatio,
			availableOutgoingKbps: availableOutgoingKbps,
			fps: fps,
			freezeCountDelta: freezeCountDelta,
			qualityLimitationReason: qualityLimitationReason,
			isRelayed: isRelayed
		)
	}

	private func score(
		_ signals: QualitySignals,
		skipBitrate: Bool = false
	) -> (quality: ConnectionQuality, limitingFactor: ConnectionQualityLimitingFactor) {
		ConnectionQualityScoring.scoreMetrics(signals, thresholds: thresholds, skipBitrate: skipBitrate)
	}

	// MARK: - scoreMetrics

	func testHealthySnapshotIsGoodWithNoLimitingFactor() {
		let result = score(makeSignals())
		XCTAssertEqual(result.quality, .good)
		XCTAssertEqual(result.limitingFactor, .none)
	}

	func testHighRttIsCriticalLatency() {
		let result = score(makeSignals(rttMs: 600))
		XCTAssertEqual(result.quality, .critical)
		XCTAssertEqual(result.limitingFactor, .latency)
	}

	func testHighPacketLossIsCriticalLoss() {
		let result = score(makeSignals(fractionLost: 0.2))
		XCTAssertEqual(result.quality, .critical)
		XCTAssertEqual(result.limitingFactor, .loss)
	}

	func testAFewPercentLossIsFairNotCritical() {
		XCTAssertEqual(score(makeSignals(fractionLost: 0.03)).quality, .fair)
	}

	func testInsufficientUpstreamHeadroomIsBandwidth() {
		// available 1000 kbps vs 3500 required → ratio 0.29 < 0.5 → critical
		let result = score(makeSignals(availableOutgoingKbps: 1000))
		XCTAssertEqual(result.quality, .critical)
		XCTAssertEqual(result.limitingFactor, .bandwidth)
	}

	func testThrottledUpstreamScoredAgainstIntendedBitrate() {
		// Even if the encoder target dropped to match a weak uplink, scoring against
		// the intended 3500 kbps still flags it.
		let result = score(makeSignals(availableOutgoingKbps: 1200))
		XCTAssertEqual(result.quality, .critical)
		XCTAssertEqual(result.limitingFactor, .bandwidth)
	}

	func testEncoderBandwidthLimitationCapsAtFair() {
		let result = score(makeSignals(availableOutgoingKbps: 6000, qualityLimitationReason: "bandwidth"))
		XCTAssertEqual(result.quality, .fair)
		XCTAssertEqual(result.limitingFactor, .bandwidth)
	}

	func testCpuLimitationIsInformationalOnly() {
		let result = score(makeSignals(qualityLimitationReason: "cpu"))
		XCTAssertEqual(result.quality, .good)
		XCTAssertEqual(result.limitingFactor, .cpu)
	}

	func testRttBandsWidenOnRelayedPaths() {
		// 250ms: fair on a direct path, good once relay adds +100ms headroom.
		XCTAssertEqual(score(makeSignals(rttMs: 250, isRelayed: false)).quality, .fair)
		XCTAssertEqual(score(makeSignals(rttMs: 250, isRelayed: true)).quality, .good)
	}

	func testSkipBitrateExcludesBandwidthDimension() {
		// low upstream headroom: critical normally, good when skipped (warm-up)
		XCTAssertEqual(score(makeSignals(availableOutgoingKbps: 1000), skipBitrate: true).quality, .good)
		XCTAssertEqual(score(makeSignals(availableOutgoingKbps: 1000)).quality, .critical)
	}

	func testMissingMetricsTreatedAsGood() {
		let allNil = makeSignals(
			rttMs: nil,
			fractionLost: nil,
			availableOutgoingKbps: nil,
			fps: nil,
			freezeCountDelta: nil,
			qualityLimitationReason: nil
		)
		let result = score(allNil)
		XCTAssertEqual(result.quality, .good)
		XCTAssertEqual(result.limitingFactor, .none)
	}

	func testFreezeDeltaDegradesStallToFair() {
		// Healthy fps but a freeze occurred this tick → at least fair.
		let result = score(makeSignals(freezeCountDelta: 1))
		XCTAssertEqual(result.quality, .fair)
		XCTAssertEqual(result.limitingFactor, .stall)
	}

	// MARK: - Glass-to-glass (PR #158)

	func testMeasuredGlassToGlassDrivesLatencyNotRtt() {
		// Low RTT alone reads good, but a high measured g2g (slow model path) pulls latency down.
		let result = score(makeSignals(rttMs: 50, g2gMs: 1800)) // > poor band (1500)
		XCTAssertEqual(result.quality, .critical)
		XCTAssertEqual(result.limitingFactor, .latency)
	}

	func testTypicalGlassToGlassIsGood() {
		// ~450ms steady-state (server pipeline ~285ms + network/jitter) is good.
		XCTAssertEqual(score(makeSignals(g2gMs: 450)).quality, .good)
	}

	func testGoodGlassToGlassIsGoodEvenOnRelay() {
		// g2g already includes the network legs, so no relay headroom applies.
		XCTAssertEqual(score(makeSignals(g2gMs: 450, isRelayed: true)).quality, .good)
	}

	func testFallsBackToRttWhenGlassToGlassAbsent() {
		XCTAssertEqual(score(makeSignals(rttMs: 600)).quality, .critical)
	}

	func testHighEndToEndDropRatioIsStall() {
		let result = score(makeSignals(g2gDropRatio: 0.2)) // > poor band (10%)
		XCTAssertEqual(result.quality, .critical)
		XCTAssertEqual(result.limitingFactor, .stall)
	}

	// MARK: - ConnectionQualityEvaluator

	private func fastThresholds(
		warmupSamples: Int = 1,
		downgradeConsecutive: Int = 3,
		upgradeConsecutive: Int = 3
	) -> ConnectionQualityThresholds {
		let d = ConnectionQualityThresholds.default
		return ConnectionQualityThresholds(
			windowSamples: 1,
			warmupSamples: warmupSamples,
			downgradeConsecutive: downgradeConsecutive,
			upgradeConsecutive: upgradeConsecutive,
			rtt: d.rtt,
			glassToGlass: d.glassToGlass,
			ttff: d.ttff,
			loss: d.loss,
			g2gDrop: d.g2gDrop,
			upstream: d.upstream,
			stall: d.stall
		)
	}

	func testEmitsFirstVerdictImmediately() {
		let evaluator = ConnectionQualityEvaluator(thresholds: fastThresholds())
		XCTAssertEqual(evaluator.update(makeSignals())?.quality, .good)
	}

	func testRequiresConsecutiveSamplesBeforeDowngradeThenUpgrade() {
		let evaluator = ConnectionQualityEvaluator(thresholds: fastThresholds())
		XCTAssertEqual(evaluator.update(makeSignals())?.quality, .good)

		let bad = { self.makeSignals(rttMs: 600) }
		XCTAssertNil(evaluator.update(bad())) // 1
		XCTAssertNil(evaluator.update(bad())) // 2
		XCTAssertEqual(evaluator.update(bad())?.quality, .critical) // 3 → downgrade
		XCTAssertEqual(evaluator.current()?.quality, .critical)

		XCTAssertNil(evaluator.update(makeSignals())) // 1
		XCTAssertNil(evaluator.update(makeSignals())) // 2
		XCTAssertEqual(evaluator.update(makeSignals())?.quality, .good) // 3 → upgrade
	}

	func testEmitsAgainWhenWarmupEndsEvenIfLevelHeld() {
		let evaluator = ConnectionQualityEvaluator(thresholds: fastThresholds(warmupSamples: 3))
		let r1 = evaluator.update(makeSignals())
		XCTAssertEqual(r1?.quality, .good)
		XCTAssertEqual(r1?.warmingUp, true)
		XCTAssertNil(evaluator.update(makeSignals())) // still warming, no change
		let r3 = evaluator.update(makeSignals()) // warm-up ends → emit
		XCTAssertEqual(r3?.quality, .good)
		XCTAssertEqual(r3?.warmingUp, false)
		XCTAssertNil(evaluator.update(makeSignals())) // steady afterward → silent
	}

	func testSnapsToRealVerdictWhenWarmupEnds() {
		let evaluator = ConnectionQualityEvaluator(thresholds: fastThresholds(warmupSamples: 3))
		let weakUplink = { self.makeSignals(availableOutgoingKbps: 800) } // ~0.23 ratio → critical
		var report = evaluator.update(weakUplink())
		XCTAssertEqual(report?.quality, .good) // bandwidth skipped during warm-up
		XCTAssertEqual(report?.warmingUp, true)
		XCTAssertNil(evaluator.update(weakUplink()))
		report = evaluator.update(weakUplink()) // warm-up ends → snap to real verdict
		XCTAssertEqual(report?.quality, .critical)
		XCTAssertEqual(report?.warmingUp, false)
		XCTAssertEqual(report?.limitingFactor, .bandwidth)
	}

	func testRefreshesLimitingFactorWhenCauseShiftsAtHeldLevel() {
		let evaluator = ConnectionQualityEvaluator(thresholds: fastThresholds())
		evaluator.update(makeSignals()) // good
		evaluator.update(makeSignals(rttMs: 600))
		evaluator.update(makeSignals(rttMs: 600))
		XCTAssertEqual(evaluator.update(makeSignals(rttMs: 600))?.limitingFactor, .latency)
		// Still critical, but latency recovered and bandwidth is now the culprit.
		evaluator.update(makeSignals(availableOutgoingKbps: 500))
		XCTAssertEqual(evaluator.current()?.quality, .critical)
		XCTAssertEqual(evaluator.current()?.limitingFactor, .bandwidth)
	}

	func testKeepsLimitingFactorOfHeldVerdictDuringRecovery() {
		let evaluator = ConnectionQualityEvaluator(thresholds: fastThresholds())
		evaluator.update(makeSignals()) // good
		let badLatency = { self.makeSignals(rttMs: 600) }
		evaluator.update(badLatency())
		evaluator.update(badLatency())
		XCTAssertEqual(evaluator.update(badLatency())?.quality, .critical) // downgrade
		XCTAssertEqual(evaluator.current()?.limitingFactor, .latency)

		// One good recovery sample: still debounced at critical — reason stays latency.
		XCTAssertNil(evaluator.update(makeSignals()))
		XCTAssertEqual(evaluator.current()?.quality, .critical)
		XCTAssertEqual(evaluator.current()?.limitingFactor, .latency)
	}

	func testResetsDebounceCounterWhenSampleReturnsToCurrentLevel() {
		let evaluator = ConnectionQualityEvaluator(thresholds: fastThresholds())
		evaluator.update(makeSignals()) // good
		let bad = { self.makeSignals(rttMs: 600) }
		XCTAssertNil(evaluator.update(bad())) // 1 bad
		XCTAssertNil(evaluator.update(bad())) // 2 bad
		XCTAssertNil(evaluator.update(makeSignals())) // good resets counter
		XCTAssertNil(evaluator.update(bad())) // 1 bad again
		XCTAssertNil(evaluator.update(bad())) // 2 bad
		XCTAssertEqual(evaluator.update(bad())?.quality, .critical) // 3 → downgrade
	}

	func testStaysProvisionalThenScoresBandwidthAfterWarmup() {
		let evaluator = ConnectionQualityEvaluator(thresholds: fastThresholds(warmupSamples: 3, downgradeConsecutive: 1))
		let lowUp = { self.makeSignals(availableOutgoingKbps: 1000) }

		let first = evaluator.update(lowUp())
		XCTAssertEqual(first?.quality, .good)
		XCTAssertEqual(first?.warmingUp, true)

		XCTAssertNil(evaluator.update(lowUp())) // still warming, still good
		XCTAssertEqual(evaluator.current()?.warmingUp, true)

		let afterWarmup = evaluator.update(lowUp()) // warm-up over → bandwidth counts
		XCTAssertEqual(afterWarmup?.warmingUp, false)
		XCTAssertEqual(afterWarmup?.quality, .critical)
	}

	func testResetClearsAllState() {
		let evaluator = ConnectionQualityEvaluator(thresholds: fastThresholds())
		evaluator.update(makeSignals(rttMs: 600))
		evaluator.reset()
		XCTAssertNil(evaluator.current())
		XCTAssertEqual(evaluator.update(makeSignals())?.quality, .good) // first verdict after reset emits again
	}

	// MARK: - RingBuffer

	func testRingBufferMedianMinAndWraparound() {
		var buffer = RingBuffer(capacity: 3)
		XCTAssertNil(buffer.median())
		XCTAssertNil(buffer.min())

		buffer.push(10)
		buffer.push(nil) // ignored
		buffer.push(30)
		XCTAssertEqual(buffer.median(), 20) // even count → average of middle two
		XCTAssertEqual(buffer.min(), 10)

		buffer.push(20)
		XCTAssertEqual(buffer.median(), 20) // [10,30,20] → sorted [10,20,30] → 20
		buffer.push(40) // evicts 10 → [30,20,40]
		buffer.push(50) // evicts 30 → [20,40,50]
		XCTAssertEqual(buffer.median(), 40)
		XCTAssertEqual(buffer.min(), 20)

		buffer.clear()
		XCTAssertNil(buffer.median())
	}
}
