import CoreImage
import CoreVideo
@preconcurrency import WebRTC

/// Forwards frames from an `RTCVideoCapturer` to an `RTCVideoSource`, optionally
/// pre-flipping each frame so the visible result is horizontally mirrored in
/// **display orientation** — i.e., after WebRTC applies the rotation carried in
/// `RTCVideoFrame.rotation`.
///
/// The buffer-space flip axis is chosen from the frame's rotation so the
/// composition (buffer flip ∘ display rotation) is always a horizontal flip in
/// display space. The output frame keeps the original rotation metadata, so
/// downstream encoders, renderers, and the server-side pipeline behave
/// identically except for the mirror.
final class MirroringVideoCapturerDelegate: NSObject, RTCVideoCapturerDelegate, @unchecked Sendable {
	private let target: RTCVideoSource
	private let ciContext: CIContext

	private var bufferPool: CVPixelBufferPool?
	private var poolWidth: Int = 0
	private var poolHeight: Int = 0
	private var poolFormat: OSType = 0

	/// Whether to mirror frames before forwarding. Toggling is best-effort; a
	/// one-frame race during a flip is acceptable.
	var shouldMirror: Bool = false

	init(target: RTCVideoSource) {
		self.target = target
		self.ciContext = CIContext()
		super.init()
	}

	func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
		guard shouldMirror, let mirrored = mirror(frame: frame) else {
			target.capturer(capturer, didCapture: frame)
			return
		}
		target.capturer(capturer, didCapture: mirrored)
	}

	private func mirror(frame: RTCVideoFrame) -> RTCVideoFrame? {
		guard let rtcBuffer = frame.buffer as? RTCCVPixelBuffer else {
			// I420 (software) buffer path — fall back to un-mirrored forwarding.
			// In practice the camera pipeline delivers CVPixelBuffer-backed frames.
			DecartLogger.log("MirroringVideoCapturerDelegate: non-CVPixelBuffer frame, passing through un-mirrored", level: .warning)
			return nil
		}

		let inputBuffer = rtcBuffer.pixelBuffer
		let width = CVPixelBufferGetWidth(inputBuffer)
		let height = CVPixelBufferGetHeight(inputBuffer)
		let format = CVPixelBufferGetPixelFormatType(inputBuffer)

		if bufferPool == nil || poolWidth != width || poolHeight != height || poolFormat != format {
			guard createPool(width: width, height: height, format: format) else { return nil }
		}
		guard let pool = bufferPool else { return nil }

		var outputBuffer: CVPixelBuffer?
		let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
		guard status == kCVReturnSuccess, let outputBuffer else { return nil }

		// Buffer holds the sensor-orientation image. `frame.rotation` says how
		// many degrees consumers must rotate it CW for display. To get a
		// horizontal flip in display, flip in the inverse axis in buffer space.
		let orientation: CGImagePropertyOrientation
		switch frame.rotation {
		case ._0, ._180: orientation = .upMirrored    // H-flip in buffer = H-flip in display (R=0/180)
		case ._90, ._270: orientation = .downMirrored // V-flip in buffer = H-flip in display (R=90/270)
		@unknown default: orientation = .upMirrored
		}

		let ciImage = CIImage(cvPixelBuffer: inputBuffer).oriented(orientation)
		ciContext.render(ciImage, to: outputBuffer)

		let mirroredBuffer = RTCCVPixelBuffer(pixelBuffer: outputBuffer)
		return RTCVideoFrame(buffer: mirroredBuffer, rotation: frame.rotation, timeStampNs: frame.timeStampNs)
	}

	private func createPool(width: Int, height: Int, format: OSType) -> Bool {
		let attrs: [CFString: Any] = [
			kCVPixelBufferPixelFormatTypeKey: format,
			kCVPixelBufferWidthKey: width,
			kCVPixelBufferHeightKey: height,
			kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
		]
		var pool: CVPixelBufferPool?
		let status = CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
		guard status == kCVReturnSuccess, let pool else {
			DecartLogger.log("MirroringVideoCapturerDelegate: CVPixelBufferPoolCreate failed (\(status))", level: .error)
			return false
		}
		self.bufferPool = pool
		self.poolWidth = width
		self.poolHeight = height
		self.poolFormat = format
		return true
	}
}
