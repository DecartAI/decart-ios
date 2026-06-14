import CoreVideo
@preconcurrency import LiveKit

/// A CPU-generated animated video source for the deep connectivity probe — no
/// camera permission needed; content is irrelevant to the marker. Produces NV12
/// frames at the requested size/fps with an animated luma ramp (so the encoder
/// emits real frames at the target rate) and stamps the glass-to-glass marker
/// directly into the Y plane via the shared `SeqTracker`.
final class SyntheticVideoSource: @unchecked Sendable {
	let track: LocalVideoTrack

	private let capturer: BufferCapturer?
	private let tracker: SeqTracker
	private let width: Int
	private let height: Int
	private let fps: Int
	private let queue = DispatchQueue(label: "ai.decart.realtime.synthetic")
	private var timer: DispatchSourceTimer?
	private var pool: CVPixelBufferPool?
	private var frameCount: UInt = 0

	init(width: Int, height: Int, fps: Int, tracker: SeqTracker) {
		self.width = width
		self.height = height
		self.fps = max(1, fps)
		self.tracker = tracker
		track = LocalVideoTrack.createBufferTrack(name: "synthetic_video", source: .camera)
		capturer = track.capturer as? BufferCapturer
	}

	/// Begin emitting frames. Emits one synchronously first — `BufferCapturer`
	/// requires ≥1 frame before the track can be published.
	func start() {
		queue.sync {
			guard timer == nil else { return }
			createPoolIfNeeded()
			emitFrame()
			let interval = DispatchTimeInterval.milliseconds(1000 / fps)
			let t = DispatchSource.makeTimerSource(queue: queue)
			t.schedule(deadline: .now() + interval, repeating: interval)
			t.setEventHandler { [weak self] in self?.emitFrame() }
			timer = t
			t.resume()
		}
	}

	func stop() {
		queue.sync {
			timer?.cancel()
			timer = nil
		}
		let track = track
		Task { try? await track.stop() }
	}

	private func emitFrame() {
		guard let pool, let capturer else { return }
		var buffer: CVPixelBuffer?
		guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return }
		fillAndStamp(buffer)
		capturer.capture(buffer, rotation: ._0)
	}

	private func fillAndStamp(_ buffer: CVPixelBuffer) {
		CVPixelBufferLockBaseAddress(buffer, [])
		defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

		// Y plane: animated luma so frames aren't deduplicated; then stamp the marker.
		if let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
			let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
			let w = CVPixelBufferGetWidthOfPlane(buffer, 0)
			let h = CVPixelBufferGetHeightOfPlane(buffer, 0)
			let luma = Int32((frameCount &* 4) % 256)
			memset(yBase, luma, bytesPerRow * h)
			let ptr = yBase.assumingMemoryBound(to: UInt8.self)
			let seq = tracker.stampNext(monotonicMs())
			PixelMarker.stamp(width: w, height: h, seq: seq) { x, y, value in
				ptr[y * bytesPerRow + x] = UInt8(value)
			}
		}
		// Chroma plane neutral (128 = gray).
		if CVPixelBufferGetPlaneCount(buffer) > 1, let uvBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
			let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
			let h = CVPixelBufferGetHeightOfPlane(buffer, 1)
			memset(uvBase, 128, bytesPerRow * h)
		}
		frameCount &+= 1
	}

	private func createPoolIfNeeded() {
		guard pool == nil else { return }
		pool = makePixelBufferPool(width: width, height: height, pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
	}
}
