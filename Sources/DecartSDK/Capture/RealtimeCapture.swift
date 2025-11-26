import AVFoundation
@preconcurrency import WebRTC

public enum CaptureOrientation: Sendable {
	case portrait
	case landscape
}

#if !targetEnvironment(simulator)
public final class RealtimeCapture: @unchecked Sendable {
	public private(set) var position: AVCaptureDevice.Position
	public let orientation: CaptureOrientation
	public let targetWidth: Int
	public let targetHeight: Int

	public var captureSession: AVCaptureSession { capturer.captureSession }

	private let model: ModelDefinition
	private let videoSource: RTCVideoSource
	private let capturer: RTCCameraVideoCapturer

	public init(
		model: ModelDefinition,
		videoSource: RTCVideoSource,
		orientation: CaptureOrientation = .portrait,
		initialPosition: AVCaptureDevice.Position = .front
	) {
		self.model = model
		self.videoSource = videoSource
		self.orientation = orientation
		self.position = initialPosition

		switch orientation {
		case .landscape:
			self.targetWidth = model.width
			self.targetHeight = model.height
		case .portrait:
			self.targetWidth = model.height
			self.targetHeight = model.width
		}

		self.capturer = RTCCameraVideoCapturer(delegate: videoSource)
	}

	public func startCapture() async throws {
		try await startCapture(position: position)
	}

	public func switchCamera() async throws {
		let newPosition: AVCaptureDevice.Position = position == .front ? .back : .front
		try await startCapture(position: newPosition)
		position = newPosition
	}

	public func stopCapture() async {
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			capturer.stopCapture { continuation.resume() }
		}

		let session = capturer.captureSession
		session.beginConfiguration()
		session.outputs.forEach { session.removeOutput($0) }
		session.inputs.forEach { session.removeInput($0) }
		session.commitConfiguration()
	}

	private func startCapture(position: AVCaptureDevice.Position) async throws {
		let device = try AVCaptureDevice.pickCamera(position: position)
		let format = try device.pickFormat(minWidth: targetWidth, minHeight: targetHeight)
		let targetFPS = try device.pickFPS(for: format, preferred: model.fps)

		videoSource.adaptOutputFormat(
			toWidth: Int32(targetWidth),
			height: Int32(targetHeight),
			fps: Int32(targetFPS)
		)

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			capturer.startCapture(with: device, format: format, fps: targetFPS) { error in
				if let error { continuation.resume(throwing: error) }
				else { continuation.resume() }
			}
		}
	}
}

private final class VideoFrameAdapter: NSObject, RTCVideoCapturerDelegate {
	private weak var targetSource: RTCVideoSource?
	let targetWidth: Int32
	let targetHeight: Int32

	init(source: RTCVideoSource, targetWidth: Int32, targetHeight: Int32) {
		self.targetSource = source
		self.targetWidth = targetWidth
		self.targetHeight = targetHeight
		super.init()
	}

	func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
		guard let source = targetSource else { return }

		guard frame.width != targetWidth || frame.height != targetHeight else {
			source.capturer(capturer, didCapture: frame)
			return
		}

		guard let adaptedFrame = cropAndScaleFromCenter(frame: frame) else {
			source.capturer(capturer, didCapture: frame)
			return
		}

		source.capturer(capturer, didCapture: adaptedFrame)
	}

	private func cropAndScaleFromCenter(frame: RTCVideoFrame) -> RTCVideoFrame? {
		let sourceWidth = frame.width
		let sourceHeight = frame.height

		let scaleWidth: Int32
		let scaleHeight: Int32

		if targetWidth > sourceWidth || targetHeight > sourceHeight {
			let widthScale = Double(targetWidth) / Double(sourceWidth)
			let heightScale = Double(targetHeight) / Double(sourceHeight)
			let scale = max(widthScale, heightScale)
			scaleWidth = Int32(Double(targetWidth) / scale)
			scaleHeight = Int32(Double(targetHeight) / scale)
		} else {
			scaleWidth = targetWidth
			scaleHeight = targetHeight
		}

		let sourceRatio = Double(sourceWidth) / Double(sourceHeight)
		let targetRatio = Double(scaleWidth) / Double(scaleHeight)

		let cropWidth: Int32
		let cropHeight: Int32

		if sourceRatio > targetRatio {
			cropHeight = sourceHeight
			cropWidth = Int32(Double(sourceHeight) * targetRatio)
		} else {
			cropWidth = sourceWidth
			cropHeight = Int32(Double(sourceWidth) / targetRatio)
		}

		let offsetX = (sourceWidth - cropWidth) / 2
		let offsetY = (sourceHeight - cropHeight) / 2

		guard let newBuffer = frame.buffer.cropAndScale?(
			with: offsetX,
			offsetY: offsetY,
			cropWidth: cropWidth,
			cropHeight: cropHeight,
			scaleWidth: scaleWidth,
			scaleHeight: scaleHeight
		) else {
			return nil
		}

		return RTCVideoFrame(buffer: newBuffer, rotation: frame.rotation, timeStampNs: frame.timeStampNs)
	}
}
#endif
