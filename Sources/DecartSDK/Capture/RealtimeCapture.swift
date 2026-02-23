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
	private var activeDeviceID: String?

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
		#if os(macOS)
		try await startCapture(position: position, fallbackToAny: true)
		#else
		try await startCapture(position: position, fallbackToAny: false)
		#endif
	}

	public func switchCamera() async throws {
		#if os(macOS)
		let devices = AVCaptureDevice.availableCameras()
		guard devices.count > 1 else { return }

		let currentDeviceID: String
		if let activeDeviceID {
			currentDeviceID = activeDeviceID
		} else {
			currentDeviceID = try AVCaptureDevice.pickCamera(
				position: position,
				fallbackToAny: true
			).uniqueID
		}
		guard let nextDevice = AVCaptureDevice.nextCamera(after: currentDeviceID) else {
			throw CameraError.noCameraDeviceAvailable
		}

		guard nextDevice.uniqueID != currentDeviceID else { return }
		try await startCapture(with: nextDevice)
		position = nextDevice.position
		#else
		let newPosition: AVCaptureDevice.Position = position == .front ? .back : .front
		try await startCapture(position: newPosition, fallbackToAny: false)
		position = newPosition
		#endif
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
		activeDeviceID = nil
	}

	private func startCapture(
		position: AVCaptureDevice.Position,
		fallbackToAny: Bool
	) async throws {
		let device = try AVCaptureDevice.pickCamera(position: position, fallbackToAny: fallbackToAny)
		try await startCapture(with: device)
		self.position = device.position
	}

	private func startCapture(with device: AVCaptureDevice) async throws {
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

		activeDeviceID = device.uniqueID
	}
}
#endif
