import AVFoundation
import CoreImage
import CoreVideo
@preconcurrency import LiveKit

/// Mirroring for input frames, applied before encoding so the server receives them
/// in display orientation (keeps server-baked content like watermarks readable).
public enum MirrorMode: Sendable {
	/// Never mirror.
	case off
	/// Mirror only the front camera.
	case auto
	/// Always mirror.
	case on
}

/// A LiveKit ``VideoProcessor`` that horizontally mirrors camera frames before
/// encoding, in display orientation. The flip axis is chosen from the frame's
/// rotation so the result is always a horizontal flip in display space, with the
/// rotation metadata preserved. For ``MirrorMode/auto``, update ``cameraPosition``
/// when the active camera changes.
public final class MirroringVideoProcessor: NSObject, VideoProcessor, @unchecked Sendable {
	private let lock = NSLock()
	private var _mode: MirrorMode
	private var _cameraPosition: AVCaptureDevice.Position

	/// Mirroring mode. Safe to set from any thread.
	public var mode: MirrorMode {
		get { lock.lock(); defer { lock.unlock() }; return _mode }
		set { lock.lock(); _mode = newValue; lock.unlock() }
	}

	/// Active camera position, used to resolve ``MirrorMode/auto``. Update on camera switch.
	public var cameraPosition: AVCaptureDevice.Position {
		get { lock.lock(); defer { lock.unlock() }; return _cameraPosition }
		set { lock.lock(); _cameraPosition = newValue; lock.unlock() }
	}

	private let ciContext: CIContext

	// Accessed only from process(frame:) on LiveKit's serial queue.
	private var bufferPool: CVPixelBufferPool?
	private var poolWidth: Int = 0
	private var poolHeight: Int = 0
	private var poolFormat: OSType = 0

	public init(mode: MirrorMode = .off, cameraPosition: AVCaptureDevice.Position = .front) {
		self._mode = mode
		self._cameraPosition = cameraPosition
		self.ciContext = CIContext()
		super.init()
	}

	public func process(frame: VideoFrame) -> VideoFrame? {
		guard shouldMirror else { return frame }
		// nil drops the frame in LiveKit, so forward the original on failure.
		return mirror(frame: frame) ?? frame
	}

	private var shouldMirror: Bool {
		lock.lock(); defer { lock.unlock() }
		switch _mode {
		case .off: return false
		case .on: return true
		case .auto: return _cameraPosition == .front
		}
	}

	private func mirror(frame: VideoFrame) -> VideoFrame? {
		guard let inputBuffer = frame.toCVPixelBuffer() else {
			DecartLogger.log("MirroringVideoProcessor: frame has no CVPixelBuffer, passing through un-mirrored", level: .warning)
			return nil
		}

		let format = CVPixelBufferGetPixelFormatType(inputBuffer)

		// Output at the frame's logical size, not the backing buffer's: LiveKit
		// carries any crop/scale to CameraCaptureOptions.dimensions as metadata that
		// toCVPixelBuffer() drops, so reproduce it here to preserve dimensions/aspect.
		let targetWidth = Int(frame.dimensions.width)
		let targetHeight = Int(frame.dimensions.height)
		guard targetWidth > 0, targetHeight > 0 else { return nil }

		if bufferPool == nil || poolWidth != targetWidth || poolHeight != targetHeight || poolFormat != format {
			guard createPool(width: targetWidth, height: targetHeight, format: format) else { return nil }
		}
		guard let pool = bufferPool else { return nil }

		var outputBuffer: CVPixelBuffer?
		let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
		guard status == kCVReturnSuccess, let outputBuffer else { return nil }

		// Flip axis depends on rotation so the result is a horizontal flip in display space.
		let orientation: CGImagePropertyOrientation
		switch frame.rotation {
		case ._0, ._180: orientation = .upMirrored    // H-flip in buffer = H-flip in display (R=0/180)
		case ._90, ._270: orientation = .downMirrored // V-flip in buffer = H-flip in display (R=90/270)
		@unknown default: orientation = .upMirrored
		}

		let ciImage = centerCropAndScale(CIImage(cvPixelBuffer: inputBuffer), toWidth: targetWidth, height: targetHeight)
			.oriented(orientation)
		ciContext.render(ciImage, to: outputBuffer)

		return VideoFrame(
			dimensions: frame.dimensions,
			rotation: frame.rotation,
			timeStampNs: frame.timeStampNs,
			buffer: CVPixelVideoBuffer(pixelBuffer: outputBuffer)
		)
	}

	/// Center-crops to the target aspect and scales to `targetWidth`×`targetHeight`
	/// (matching LiveKit's `cropAndScaleFromCenter`); returns `image` if already sized.
	private func centerCropAndScale(_ image: CIImage, toWidth targetWidth: Int, height targetHeight: Int) -> CIImage {
		let extent = image.extent
		guard Int(extent.width) != targetWidth || Int(extent.height) != targetHeight else {
			return image
		}

		let target = CGFloat(targetWidth) / CGFloat(targetHeight)
		let source = extent.width / extent.height

		var cropWidth = extent.width
		var cropHeight = extent.height
		if source > target {
			cropWidth = extent.height * target // source is wider — crop the sides
		} else {
			cropHeight = extent.width / target // source is taller — crop top/bottom
		}
		let cropX = extent.origin.x + (extent.width - cropWidth) / 2
		let cropY = extent.origin.y + (extent.height - cropHeight) / 2

		return image
			.cropped(to: CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight))
			.transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))
			.transformed(by: CGAffineTransform(scaleX: CGFloat(targetWidth) / cropWidth, y: CGFloat(targetHeight) / cropHeight))
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
			DecartLogger.log("MirroringVideoProcessor: CVPixelBufferPoolCreate failed (\(status))", level: .error)
			return false
		}
		self.bufferPool = pool
		self.poolWidth = width
		self.poolHeight = height
		self.poolFormat = format
		return true
	}
}
