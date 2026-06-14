import XCTest
@testable import DecartSDK

/// Ports the `classifyConnectivity` cases from `preflight.unit.test.ts`. The
/// `NWConnection` STUN probe itself is integration-tested manually (CI can't
/// guarantee outbound UDP to STUN) — only the pure classifier is unit-tested.
final class PreflightClassifierTests: XCTestCase {
	private let rtt = PreflightRttThresholds(goodMs: 150, marginalMs: 300)

	func testFailedIsCritical() {
		let report = classifyConnectivity(metrics: ConnectivityMetrics(transport: .failed, rttMs: nil), thresholds: rtt)
		XCTAssertEqual(report.quality, .critical)
		XCTAssertFalse(report.reasons.isEmpty)
		XCTAssertEqual(report.metrics, ConnectivityMetrics(transport: .failed, rttMs: nil))
	}

	func testRelayIsPoor() {
		let report = classifyConnectivity(metrics: ConnectivityMetrics(transport: .relay, rttMs: 90), thresholds: rtt)
		XCTAssertEqual(report.quality, .poor)
		XCTAssertFalse(report.reasons.isEmpty)
	}

	func testDirectUdpLowRttIsGood() {
		let report = classifyConnectivity(metrics: ConnectivityMetrics(transport: .udp, rttMs: 100), thresholds: rtt)
		XCTAssertEqual(report.quality, .good)
		XCTAssertTrue(report.reasons.isEmpty)
		XCTAssertEqual(report.metrics.rttMs, 100)
	}

	func testElevatedRttIsFair() {
		let report = classifyConnectivity(metrics: ConnectivityMetrics(transport: .udp, rttMs: 200), thresholds: rtt)
		XCTAssertEqual(report.quality, .fair)
	}

	func testVeryHighRttIsPoor() {
		let report = classifyConnectivity(metrics: ConnectivityMetrics(transport: .udp, rttMs: 420), thresholds: rtt)
		XCTAssertEqual(report.quality, .poor)
	}

	func testDirectUdpUnknownRttIsGood() {
		let report = classifyConnectivity(metrics: ConnectivityMetrics(transport: .udp, rttMs: nil), thresholds: rtt)
		XCTAssertEqual(report.quality, .good)
	}

	// MARK: - classifyActiveProbe (deep probe, PR #158)

	private func probeMetrics(
		transport: ConnectivityTransport = .udp,
		rttMs: Int? = 50,
		g2gMs: Double? = 450,
		ttffMs: Double? = 2_000,
		g2gDropRatio: Double? = 0,
		upstreamJitterMs: Double? = 5,
		packetLoss: Double? = 0,
		sampleCount: Int? = 30
	) -> ConnectivityMetrics {
		ConnectivityMetrics(
			transport: transport,
			rttMs: rttMs,
			g2gMs: g2gMs,
			ttffMs: ttffMs,
			g2gDropRatio: g2gDropRatio,
			upstreamJitterMs: upstreamJitterMs,
			packetLoss: packetLoss,
			sampleCount: sampleCount
		)
	}

	func testActiveFastStartupLowLatencyIsGood() {
		let report = classifyActiveProbe(metrics: probeMetrics(g2gMs: 450, ttffMs: 2_000))
		XCTAssertEqual(report.quality, .good)
		XCTAssertTrue(report.reasons.isEmpty)
	}

	func testActiveDrivenByGlassToGlassEvenWhenRttLow() {
		let report = classifyActiveProbe(metrics: probeMetrics(rttMs: 30, g2gMs: 1800)) // > poor band (1500)
		XCTAssertEqual(report.quality, .critical)
		XCTAssertTrue(report.reasons.contains { $0.contains("glass-to-glass") })
	}

	func testActiveTtffScoredSeparately() {
		let report = classifyActiveProbe(metrics: probeMetrics(g2gMs: 450, ttffMs: 12_000)) // > poor band (10s)
		XCTAssertEqual(report.quality, .critical)
		XCTAssertTrue(report.reasons.contains { $0.contains("first frame") })
	}

	func testActiveColdStartIsFair() {
		let report = classifyActiveProbe(metrics: probeMetrics(g2gMs: 450, ttffMs: 4_500)) // within fair band (≤6s)
		XCTAssertEqual(report.quality, .fair)
	}

	func testActiveFallsBackToRttWhenLatencyUnmeasured() {
		let report = classifyActiveProbe(metrics: probeMetrics(
			rttMs: 600, g2gMs: nil, ttffMs: nil, g2gDropRatio: nil, packetLoss: nil
		))
		XCTAssertEqual(report.quality, .critical) // RTT 600 > poor band (500)
		XCTAssertTrue(report.reasons.contains { $0.contains("Could not measure") })
	}

	func testActiveHighDropRatioEvenWhenLatencyGood() {
		let report = classifyActiveProbe(metrics: probeMetrics(g2gMs: 150, g2gDropRatio: 0.2))
		XCTAssertEqual(report.quality, .critical)
	}

	func testActiveHighUpstreamLoss() {
		let report = classifyActiveProbe(metrics: probeMetrics(g2gMs: 150, packetLoss: 0.2))
		XCTAssertEqual(report.quality, .critical)
	}

	func testActiveFailedIsCritical() {
		let report = classifyActiveProbe(metrics: probeMetrics(transport: .failed))
		XCTAssertEqual(report.quality, .critical)
		XCTAssertFalse(report.reasons.isEmpty)
	}

	func testActiveConnectedButUnmeasuredIsFair() {
		let report = classifyActiveProbe(metrics: probeMetrics(
			rttMs: nil, g2gMs: nil, ttffMs: nil, g2gDropRatio: nil, packetLoss: nil
		))
		XCTAssertEqual(report.quality, .fair)
		XCTAssertFalse(report.reasons.isEmpty)
	}

	func testStunServerUrlParsing() {
		let parsed = STUNServer(url: "stun:stun.l.google.com:19302")
		XCTAssertEqual(parsed?.host, "stun.l.google.com")
		XCTAssertEqual(parsed?.port, 19302)

		let noPort = STUNServer(url: "stun:stun.example.com")
		XCTAssertEqual(noPort?.host, "stun.example.com")
		XCTAssertEqual(noPort?.port, 3478) // default

		XCTAssertNil(STUNServer(url: "stun:"))
	}
}
