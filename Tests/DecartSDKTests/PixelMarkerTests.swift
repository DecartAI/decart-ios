import XCTest
@testable import DecartSDK

/// Ports `pixel-marker.unit.test.ts`. Verifies the stamp/read codec round-trips
/// seqs and survives transport scaling / corruption, byte-compatible with the
/// server protocol.
final class PixelMarkerTests: XCTestCase {
	private func makeImage(_ width: Int, _ height: Int, fill: UInt8 = 0) -> PixelMarkerImage {
		var data = [UInt8](repeating: 0, count: width * height * 4)
		for i in 0..<(width * height) {
			data[i * 4] = fill
			data[i * 4 + 1] = fill
			data[i * 4 + 2] = fill
			data[i * 4 + 3] = 255
		}
		return PixelMarkerImage(width: width, height: height, data: data)
	}

	/// Uniform nearest-neighbor scale — stands in for WebRTC transport up/downscaling.
	private func scaleNearest(_ img: PixelMarkerImage, _ factor: Double) -> PixelMarkerImage {
		let width = Int((Double(img.width) * factor).rounded())
		let height = Int((Double(img.height) * factor).rounded())
		var data = [UInt8](repeating: 0, count: width * height * 4)
		for y in 0..<height {
			for x in 0..<width {
				let sx = min(img.width - 1, Int(Double(x) / factor))
				let sy = min(img.height - 1, Int(Double(y) / factor))
				let so = (sy * img.width + sx) * 4
				let o = (y * width + x) * 4
				data[o] = img.data[so]
				data[o + 1] = img.data[so + 1]
				data[o + 2] = img.data[so + 2]
				data[o + 3] = 255
			}
		}
		return PixelMarkerImage(width: width, height: height, data: data)
	}

	func testRoundTripsSweepOfSeqs() {
		for seq in [0, 1, 2, 42, 255, 256, 1000, 0x1234, 0x7fff, 0xabcd, 0xffff] {
			var img = makeImage(256, 256)
			XCTAssertTrue(PixelMarker.stamp(&img, seq: seq))
			XCTAssertEqual(PixelMarker.read(img), seq)
		}
	}

	func testMasksTo16Bits() {
		var img = makeImage(256, 256)
		PixelMarker.stamp(&img, seq: 70_000) // 70000 & 0xffff == 4464
		XCTAssertEqual(PixelMarker.read(img), 70_000 & 0xffff)
	}

	func testNoOpAndRefusesReadOnTooSmallFrame() {
		var tiny = makeImage(PixelMarker.minMarkerWidth - 1, PixelMarker.minMarkerHeight - 1)
		XCTAssertFalse(PixelMarker.stamp(&tiny, seq: 5))
		XCTAssertNil(PixelMarker.read(tiny))
	}

	func testRecoversSeqAfterDownscale() {
		var img = makeImage(256, 256)
		PixelMarker.stamp(&img, seq: 0x2bcd)
		XCTAssertEqual(PixelMarker.read(scaleNearest(img, 0.5)), 0x2bcd) // block 8 -> 4
	}

	func testRecoversSeqAfterUpscale() {
		var img = makeImage(256, 256)
		PixelMarker.stamp(&img, seq: 0x0777)
		XCTAssertEqual(PixelMarker.read(scaleNearest(img, 2)), 0x0777) // block 8 -> 16
	}

	func testReturnsNilOnUnstampedFrame() {
		XCTAssertNil(PixelMarker.read(makeImage(256, 256, fill: 0)))
		XCTAssertNil(PixelMarker.read(makeImage(256, 256, fill: 128)))
		XCTAssertNil(PixelMarker.read(makeImage(256, 256, fill: 255)))
	}

	func testRejectsCorruptedMarkerViaChecksum() {
		var img = makeImage(256, 256)
		PixelMarker.stamp(&img, seq: 0x1234)
		let width = img.width
		let height = img.height
		let logCol = 4 // first data bit
		for logRow in 0..<4 {
			let row = height - (4 - logRow) * 8 + 4
			let sampleOffset = (row * width + (logCol * 8 + 4)) * 4
			let flipped: UInt8 = img.data[sampleOffset] >= 128 ? 50 : 200
			for bx in 0..<8 {
				let o = (row * width + (logCol * 8 + bx)) * 4
				img.data[o] = flipped
				img.data[o + 1] = flipped
				img.data[o + 2] = flipped
			}
		}
		XCTAssertNil(PixelMarker.read(img))
	}

	func testSurvivesSingleCorruptedRowViaMajorityVote() {
		var img = makeImage(256, 256)
		PixelMarker.stamp(&img, seq: 0x5a5a)
		let width = img.width
		let height = img.height
		let row = height - 4 * 8 + 4 // topmost redundant row (logRow 0)
		for x in 0..<width {
			let o = (row * width + x) * 4
			img.data[o] = 123
			img.data[o + 1] = 123
			img.data[o + 2] = 123
		}
		XCTAssertEqual(PixelMarker.read(img), 0x5a5a)
	}
}
