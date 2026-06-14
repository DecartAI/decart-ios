import XCTest
@testable import DecartSDK

/// Ports `glass-to-glass.unit.test.ts`. Mid-stream samples are only counted past a
/// 2s warm-up after the first frame, so tests establish a first frame, then feed
/// steady-state samples well past it.
final class GlassToGlassTests: XCTestCase {
	private let pastWarmup = 5_000.0

	func testAllocatesMonotonic16BitSeqsThatWrap() {
		let t = SeqTracker()
		XCTAssertEqual(t.stampNext(0), 0)
		XCTAssertEqual(t.stampNext(0), 1)
		XCTAssertEqual(t.stampNext(0), 2)

		let t2 = SeqTracker()
		var last = -1
		for _ in 0..<0xffff { last = t2.stampNext(0) }
		XCTAssertEqual(last, 0xffff - 1)
		XCTAssertEqual(t2.stampNext(0), 0xffff)
		XCTAssertEqual(t2.stampNext(0), 0) // wrap
	}

	func testMeasuresTimeToFirstFrame() {
		let t = SeqTracker()
		t.markStart(1_000)
		let seq = t.stampNext(1_100)
		t.recordInbound(seq, 6_000) // first frame at 6000 → TTFF = 6000 - 1000
		let snap = t.snapshot()
		XCTAssertEqual(snap.ttffMs, 5_000)
		// The first frame is the cold-start frame; it does not count toward mid-stream.
		XCTAssertEqual(snap.sampleCount, 0)
		XCTAssertNil(snap.medianMs)
	}

	func testMidStreamPercentilesExcludingWarmup() {
		let t = SeqTracker()
		t.markStart(0)
		let warm = t.stampNext(0)
		t.recordInbound(warm, 10) // first frame establishes warm-up window (not a sample)

		for latency in [100.0, 200, 150, 300, 250] {
			let seq = t.stampNext(pastWarmup)
			t.recordInbound(seq, pastWarmup + latency)
		}
		let snap = t.snapshot()
		XCTAssertEqual(snap.sampleCount, 5)
		XCTAssertEqual(snap.medianMs, 200) // sorted [100,150,200,250,300]
		XCTAssertEqual(snap.p90Ms, 300)
	}

	func testEvenCountMedianAveragesTwoMiddleSamples() {
		let t = SeqTracker()
		t.markStart(0)
		let warm = t.stampNext(0)
		t.recordInbound(warm, 10)

		for latency in [100.0, 200, 150, 300] {
			let seq = t.stampNext(pastWarmup)
			t.recordInbound(seq, pastWarmup + latency)
		}
		let snap = t.snapshot()
		XCTAssertEqual(snap.sampleCount, 4)
		XCTAssertEqual(snap.medianMs, 175) // sorted [100,150,200,300] -> (150 + 200) / 2
	}

	func testIgnoresUnknownDuplicateAndImplausibleSeqs() {
		let t = SeqTracker()
		let warm = t.stampNext(0)
		t.recordInbound(warm, 0) // first frame

		let seq = t.stampNext(pastWarmup)
		t.recordInbound(9999, pastWarmup + 10) // unknown seq
		t.recordInbound(seq, pastWarmup + 120) // valid -> 120ms
		t.recordInbound(seq, pastWarmup + 130) // duplicate (already consumed) -> ignored
		let seq2 = t.stampNext(pastWarmup + 1_000)
		t.recordInbound(seq2, pastWarmup + 500) // negative delta -> ignored
		let snap = t.snapshot()
		XCTAssertEqual(snap.sampleCount, 1)
		XCTAssertEqual(snap.medianMs, 120)
	}

	func testReportsNilDropRatioUntilEnoughOutcomes() {
		let t = SeqTracker()
		let warm = t.stampNext(0)
		t.recordInbound(warm, 0)
		let seq = t.stampNext(pastWarmup)
		t.recordInbound(seq, pastWarmup + 50)
		XCTAssertNil(t.snapshot().dropRatio) // 1 outcome < DROP_MIN_OUTCOMES
	}

	func testInfersDropsFromSeqsThatAgeOutUnmatched() {
		let t = SeqTracker()
		let warm = t.stampNext(0)
		t.recordInbound(warm, 0) // first frame; subsequent stamps are post-warm-up

		// Stamp 286 past warm-up: 30 oldest (beyond MAX_PENDING=256) age out -> 30 drops.
		var seqs: [Int] = []
		for _ in 0..<286 { seqs.append(t.stampNext(pastWarmup)) }
		// Deliver 20 of the still-pending seqs.
		for i in 100..<120 { t.recordInbound(seqs[i], pastWarmup + 100) }
		let snap = t.snapshot()
		// 30 dropped + 20 delivered = 50 outcomes -> 0.6 drop ratio.
		XCTAssertEqual(snap.dropRatio ?? -1, 0.6, accuracy: 1e-5)
		XCTAssertEqual(snap.sampleCount, 20)
	}

	func testDoesNotCountPreFirstFrameStampsAsDrops() {
		let t = SeqTracker()
		t.markStart(0)
		// 300 stamps before any frame ever renders (e.g. while still connecting).
		for i in 0..<300 { _ = t.stampNext(Double(i)) }
		// No match yet -> no outcomes recorded despite > MAX_PENDING evictions.
		XCTAssertNil(t.snapshot().dropRatio)
	}

	func testResetClearsStateButKeepsSeqMonotonic() {
		let t = SeqTracker()
		t.markStart(0)
		let seq = t.stampNext(0)
		t.recordInbound(seq, 100)
		t.reset()
		XCTAssertEqual(t.snapshot(), G2GMetrics(ttffMs: nil, medianMs: nil, p90Ms: nil, sampleCount: 0, dropRatio: nil))
		XCTAssertEqual(t.stampNext(0), 1) // continues, not reset to 0
	}
}
