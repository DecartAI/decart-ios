import CoreVideo
@preconcurrency import LiveKit

/// Passively reads the glass-to-glass pixel marker off the rendered remote video.
/// Attached as a `VideoRenderer` on the remote track (a track can drive multiple
/// renderers), it reads the bottom band of the **luma (Y) plane** per frame and
/// feeds matched seqs to the shared `SeqTracker` — it never consumes or
/// re-encodes the track the consumer displays.
///
/// Reads I420 frames (the usual decoder output) directly off `dataY`; falls back
/// to a `CVPixelBuffer` plane-0 read otherwise.
final class MarkerReader: VideoRenderer, @unchecked Sendable {
	private let tracker: SeqTracker

	init(tracker: SeqTracker) {
		self.tracker = tracker
	}

	nonisolated var isAdaptiveStreamEnabled: Bool { false }
	nonisolated var adaptiveStreamSize: CGSize { .zero }
	nonisolated func set(size _: CGSize) {}

	nonisolated func render(frame: VideoFrame) {
		let width = Int(frame.dimensions.width)
		let height = Int(frame.dimensions.height)
		guard width > 0, height > 0 else { return }

		let seq: Int?
		if let i420 = frame.buffer as? I420VideoBuffer {
			let dataY = i420.dataY
			let strideY = Int(i420.strideY)
			seq = PixelMarker.read(width: width, height: height) { x, y in Int(dataY[y * strideY + x]) }
		} else if let cv = frame.buffer as? CVPixelVideoBuffer {
			seq = readLumaPlane(cv.pixelBuffer)
		} else {
			seq = nil
		}

		if let seq { tracker.recordInbound(seq, monotonicMs()) }
	}

	private func readLumaPlane(_ buffer: CVPixelBuffer) -> Int? {
		buffer.withLumaPlane(readOnly: true) { ptr, width, height, bytesPerRow in
			PixelMarker.read(width: width, height: height) { x, y in Int(ptr[y * bytesPerRow + x]) }
		} ?? nil
	}
}
