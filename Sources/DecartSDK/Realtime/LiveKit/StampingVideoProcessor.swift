import AVFoundation
import CoreImage
import CoreVideo
@preconcurrency import LiveKit

/// Outgoing-frame processor for the opt-in glass-to-glass measurement. Uprights
/// each frame (consuming the camera's rotation metadata), optionally mirrors the
/// front camera, then stamps a monotonic sequence marker into the bottom-left of
/// the **display-oriented** luma (Y) plane — where the server's `pixel_latency`
/// mode reads it.
///
/// The marker protocol operates in *display* space, so we must bake the rotation
/// into the pixels (and emit rotation `._0`): the server reads the raw decoded
/// buffer without applying rotation, so a rotated camera buffer would hide the
/// marker. Used only under `debugQuality`, so the normal mirror/no-processor paths
/// are unaffected.
///
/// Note: the exact rotation→orientation mapping is verified on-device; if the
/// marker doesn't round-trip on a rotated source, the orientation constants below
/// are the first thing to check (cf. the Android port's rotation fix).
public final class StampingVideoProcessor: NSObject, VideoProcessor, @unchecked Sendable {
	private let lock = NSLock()
	private let mode: MirrorMode
	private var _cameraPosition: AVCaptureDevice.Position
	private let tracker: SeqTracker
	private let ciContext = CIContext()

	// Accessed only from process(frame:) on LiveKit's serial capture queue.
	private var bufferPool: CVPixelBufferPool?
	private var poolWidth = 0
	private var poolHeight = 0
	private let outputFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange

	/// Active camera position, used to resolve ``MirrorMode/auto``. Update on camera switch.
	public var cameraPosition: AVCaptureDevice.Position {
		get { lock.lock(); defer { lock.unlock() }; return _cameraPosition }
		set { lock.lock(); _cameraPosition = newValue; lock.unlock() }
	}

	private var shouldMirror: Bool {
		lock.lock(); defer { lock.unlock() }
		switch mode {
		case .off: return false
		case .on: return true
		case .auto: return _cameraPosition == .front
		}
	}

	init(mode: MirrorMode, cameraPosition: AVCaptureDevice.Position, tracker: SeqTracker) {
		self.mode = mode
		_cameraPosition = cameraPosition
		self.tracker = tracker
		super.init()
	}

	public func process(frame: VideoFrame) -> VideoFrame? {
		// nil drops the frame in LiveKit, so forward the original on failure.
		stampedFrame(from: frame) ?? frame
	}

	private func stampedFrame(from frame: VideoFrame) -> VideoFrame? {
		guard let inputBuffer = frame.toCVPixelBuffer() else { return nil }

		// Crop/scale in buffer orientation to the intended size, then upright (+ mirror).
		let cropped = centerCropAndScale(
			CIImage(cvPixelBuffer: inputBuffer),
			toWidth: Int(frame.dimensions.width),
			height: Int(frame.dimensions.height)
		)
		let oriented = cropped.oriented(uprightOrientation(for: frame.rotation, mirror: shouldMirror))
		let normalized = oriented.transformed(
			by: CGAffineTransform(translationX: -oriented.extent.origin.x, y: -oriented.extent.origin.y)
		)

		let outWidth = Int(oriented.extent.width.rounded())
		let outHeight = Int(oriented.extent.height.rounded())
		guard outWidth > 0, outHeight > 0 else { return nil }

		if bufferPool == nil || poolWidth != outWidth || poolHeight != outHeight {
			guard createPool(width: outWidth, height: outHeight) else { return nil }
		}
		guard let pool = bufferPool else { return nil }

		var outputBuffer: CVPixelBuffer?
		guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer) == kCVReturnSuccess,
			let outputBuffer else { return nil }

		ciContext.render(normalized, to: outputBuffer)
		stampLumaPlane(outputBuffer, seq: tracker.stampNext(monotonicMs()))

		// Rotation was consumed by the upright step — emit ._0.
		return VideoFrame(
			dimensions: Dimensions(width: Int32(outWidth), height: Int32(outHeight)),
			rotation: ._0,
			timeStampNs: frame.timeStampNs,
			buffer: CVPixelVideoBuffer(pixelBuffer: outputBuffer)
		)
	}

	/// Upright the sensor buffer into display space (baking rotation), optionally
	/// applying a display-space horizontal flip for the front camera.
	private func uprightOrientation(for rotation: VideoRotation, mirror: Bool) -> CGImagePropertyOrientation {
		switch (rotation, mirror) {
		case (._0, false): return .up
		case (._90, false): return .right
		case (._180, false): return .down
		case (._270, false): return .left
		case (._0, true): return .upMirrored
		case (._90, true): return .rightMirrored
		case (._180, true): return .downMirrored
		case (._270, true): return .leftMirrored
		@unknown default: return mirror ? .upMirrored : .up
		}
	}

	private func stampLumaPlane(_ buffer: CVPixelBuffer, seq: Int) {
		guard CVPixelBufferGetPlaneCount(buffer) >= 1 else { return }
		CVPixelBufferLockBaseAddress(buffer, [])
		defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
		guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return }
		let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
		let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
		let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
		let ptr = base.assumingMemoryBound(to: UInt8.self)
		PixelMarker.stamp(width: width, height: height, seq: seq) { x, y, value in
			ptr[y * bytesPerRow + x] = UInt8(value)
		}
	}

	/// Center-crops to the target aspect and scales to `targetWidth`×`targetHeight`
	/// (matching LiveKit's `cropAndScaleFromCenter`); returns `image` if already sized.
	private func centerCropAndScale(_ image: CIImage, toWidth targetWidth: Int, height targetHeight: Int) -> CIImage {
		let extent = image.extent
		guard extent.width > 0, extent.height > 0,
			Int(extent.width) != targetWidth || Int(extent.height) != targetHeight else {
			return image
		}

		let target = CGFloat(targetWidth) / CGFloat(targetHeight)
		let source = extent.width / extent.height

		var cropWidth = extent.width
		var cropHeight = extent.height
		if source > target {
			cropWidth = extent.height * target
		} else {
			cropHeight = extent.width / target
		}
		let cropX = extent.origin.x + (extent.width - cropWidth) / 2
		let cropY = extent.origin.y + (extent.height - cropHeight) / 2

		return image
			.cropped(to: CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight))
			.transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))
			.transformed(by: CGAffineTransform(scaleX: CGFloat(targetWidth) / cropWidth, y: CGFloat(targetHeight) / cropHeight))
	}

	private func createPool(width: Int, height: Int) -> Bool {
		let attrs: [CFString: Any] = [
			kCVPixelBufferPixelFormatTypeKey: outputFormat,
			kCVPixelBufferWidthKey: width,
			kCVPixelBufferHeightKey: height,
			kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
		]
		var pool: CVPixelBufferPool?
		guard CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool) == kCVReturnSuccess, let pool else {
			DecartLogger.log("StampingVideoProcessor: CVPixelBufferPoolCreate failed", level: .error)
			return false
		}
		bufferPool = pool
		poolWidth = width
		poolHeight = height
		return true
	}
}
