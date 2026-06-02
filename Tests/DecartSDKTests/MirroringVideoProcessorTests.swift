import AVFoundation
import CoreVideo
@preconcurrency import LiveKit
import XCTest
@testable import DecartSDK

final class MirroringVideoProcessorTests: XCTestCase {
	// 32BGRA bytes are laid out B, G, R, A in memory.
	private let blue: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)
	private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)

	private let width = 4
	private let height = 2

	// MARK: - Helpers

	/// Builds a 32BGRA buffer with left/right colored halves. `bufferWidth`/
	/// `bufferHeight` size the backing buffer; a smaller `dimensions` simulates
	/// LiveKit's metadata crop/scale.
	private func makeFrame(
		left: (UInt8, UInt8, UInt8, UInt8),
		right: (UInt8, UInt8, UInt8, UInt8),
		rotation: VideoRotation = ._0,
		bufferWidth: Int? = nil,
		bufferHeight: Int? = nil,
		dimensions: (Int, Int)? = nil
	) -> VideoFrame {
		let bw = bufferWidth ?? width
		let bh = bufferHeight ?? height
		var buffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(
			kCFAllocatorDefault, bw, bh,
			kCVPixelFormatType_32BGRA,
			[kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary,
			&buffer
		)
		guard status == kCVReturnSuccess, let buffer else {
			fatalError("Failed to create pixel buffer (\(status))")
		}

		CVPixelBufferLockBaseAddress(buffer, [])
		let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
		let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
		for y in 0 ..< bh {
			for x in 0 ..< bw {
				let px = base + y * bytesPerRow + x * 4
				let color = x < bw / 2 ? left : right
				px[0] = color.0; px[1] = color.1; px[2] = color.2; px[3] = color.3
			}
		}
		CVPixelBufferUnlockBaseAddress(buffer, [])

		let dims = dimensions ?? (bw, bh)
		return VideoFrame(
			dimensions: Dimensions(width: Int32(dims.0), height: Int32(dims.1)),
			rotation: rotation,
			timeStampNs: 0,
			buffer: CVPixelVideoBuffer(pixelBuffer: buffer)
		)
	}

	/// Returns whether the pixel at (x, 0) is more red than blue.
	private func isReddish(_ frame: VideoFrame, x: Int) -> Bool {
		let buffer = frame.toCVPixelBuffer()!
		CVPixelBufferLockBaseAddress(buffer, .readOnly)
		defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
		let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
		let px = base + x * 4 // row 0
		let b = px[0], r = px[2]
		return r > b
	}

	// MARK: - Tests

	func testOnMirrorsHorizontally() throws {
		let processor = MirroringVideoProcessor(mode: .on)
		let input = makeFrame(left: blue, right: red)

		// Sanity: input left is blue, right is red.
		XCTAssertFalse(isReddish(input, x: 0))
		XCTAssertTrue(isReddish(input, x: width - 1))

		let output = try XCTUnwrap(processor.process(frame: input))

		// After a horizontal flip the colors swap sides.
		XCTAssertTrue(isReddish(output, x: 0), "left edge should now be red")
		XCTAssertFalse(isReddish(output, x: width - 1), "right edge should now be blue")
	}

	func testOffPassesThroughUnchanged() {
		let processor = MirroringVideoProcessor(mode: .off)
		let input = makeFrame(left: blue, right: red)

		let output = processor.process(frame: input)

		// Off returns the exact same frame, untouched.
		XCTAssertTrue(output === input)
	}

	func testAutoMirrorsFrontCameraOnly() throws {
		let processor = MirroringVideoProcessor(mode: .auto, cameraPosition: .front)

		let frontOutput = try XCTUnwrap(processor.process(frame: makeFrame(left: blue, right: red)))
		XCTAssertTrue(isReddish(frontOutput, x: 0), "front camera should be mirrored")

		processor.cameraPosition = .back
		let backInput = makeFrame(left: blue, right: red)
		let backOutput = processor.process(frame: backInput)
		XCTAssertTrue(backOutput === backInput, "back camera should pass through unchanged")
	}

	func testNeverDropsAValidFrame() {
		for mode in [MirrorMode.off, .on, .auto] {
			let processor = MirroringVideoProcessor(mode: mode)
			XCTAssertNotNil(
				processor.process(frame: makeFrame(left: blue, right: red)),
				"process(frame:) must not return nil (would drop the frame) for mode \(mode)"
			)
		}
	}

	func testPreservesAdaptedDimensions() throws {
		// Backing buffer is 8×2 but the frame's logical size is 4×2 — simulating
		// LiveKit's center crop/scale carried as metadata. The mirrored output
		// must match the logical dimensions, not the full backing buffer.
		let processor = MirroringVideoProcessor(mode: .on)
		let input = makeFrame(left: blue, right: red, bufferWidth: 8, bufferHeight: 2, dimensions: (4, 2))

		let output = try XCTUnwrap(processor.process(frame: input))

		let outBuffer = try XCTUnwrap(output.toCVPixelBuffer())
		XCTAssertEqual(CVPixelBufferGetWidth(outBuffer), 4, "output must be cropped/scaled to the logical width")
		XCTAssertEqual(CVPixelBufferGetHeight(outBuffer), 2)
		XCTAssertEqual(output.dimensions.width, 4)

		// Center-cropping 8→aspect-2 keeps the inner columns (blue|red), and the
		// mirror swaps them.
		XCTAssertTrue(isReddish(output, x: 0), "left edge should be red after mirror")
		XCTAssertFalse(isReddish(output, x: 3), "right edge should be blue after mirror")
	}

	func testRotatedFrameKeepsRotationMetadata() throws {
		let processor = MirroringVideoProcessor(mode: .on)
		let input = makeFrame(left: blue, right: red, rotation: ._90)
		let output = try XCTUnwrap(processor.process(frame: input))
		XCTAssertEqual(output.rotation, ._90)
		XCTAssertEqual(output.timeStampNs, input.timeStampNs)
	}
}
