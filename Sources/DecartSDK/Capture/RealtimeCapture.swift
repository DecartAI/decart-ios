import AVFoundation
@preconcurrency import WebRTC

public enum CaptureOrientation: Sendable {
	case portrait
	case landscape
}

/// Pre-flips the input video horizontally before frames reach the WebRTC encoder.
///
/// Use this when the server bakes pixel-level content (e.g. watermarks) into the
/// output and you want the client to render the result without an extra UI flip
/// that would also flip that baked content.
public enum MirrorMode: Sendable {
	/// Never mirror the input.
	case off
	/// Mirror only when the active camera is the front (`.front`) device.
	case auto
	/// Always mirror the input.
	case on
}

#if !targetEnvironment(simulator)
public final class RealtimeCapture: @unchecked Sendable {
	public private(set) var position: AVCaptureDevice.Position
	public let orientation: CaptureOrientation
	public let targetWidth: Int
	public let targetHeight: Int

	/// Controls whether input frames are pre-flipped horizontally before encoding.
	///
	/// Setting this updates the active capture pipeline; the next emitted frame
	/// reflects the new mode.
	public var mirror: MirrorMode {
		didSet { updateMirroringState() }
	}

	public var captureSession: AVCaptureSession { capturer.captureSession }

	private let model: ModelDefinition
	private let videoSource: RTCVideoSource
	private let mirroringDelegate: MirroringVideoCapturerDelegate
	private let capturer: RTCCameraVideoCapturer
	private var activeDeviceID: String?

	public init(
		model: ModelDefinition,
		videoSource: RTCVideoSource,
		orientation: CaptureOrientation = .portrait,
		initialPosition: AVCaptureDevice.Position = .front,
		mirror: MirrorMode = .off
	) {
		self.model = model
		self.videoSource = videoSource
		self.orientation = orientation
		self.position = initialPosition
		self.mirror = mirror

		switch orientation {
		case .landscape:
			self.targetWidth = model.width
			self.targetHeight = model.height
		case .portrait:
			self.targetWidth = model.height
			self.targetHeight = model.width
		}

		let delegate = MirroringVideoCapturerDelegate(target: videoSource)
		self.mirroringDelegate = delegate
		self.capturer = RTCCameraVideoCapturer(delegate: delegate)

		// `didSet` doesn't fire during `init`; push the initial state explicitly.
		delegate.shouldMirror = Self.resolveShouldMirror(mode: mirror, position: initialPosition)
	}

	public func startCapture() async throws {
		#if os(macOS)
		try await startCapture(devicePosition: position, fallbackToAny: true)
		#else
		try await startCapture(devicePosition: position, fallbackToAny: false)
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
		#else
		let newPosition: AVCaptureDevice.Position = position == .front ? .back : .front
		try await startCapture(devicePosition: newPosition, fallbackToAny: false)
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
		devicePosition: AVCaptureDevice.Position,
		fallbackToAny: Bool
	) async throws {
		let device = try AVCaptureDevice.pickCamera(position: devicePosition, fallbackToAny: fallbackToAny)
		try await startCapture(with: device)
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
		position = device.position
		updateMirroringState()
	}

	private func updateMirroringState() {
		mirroringDelegate.shouldMirror = Self.resolveShouldMirror(mode: mirror, position: position)
	}

	private static func resolveShouldMirror(
		mode: MirrorMode,
		position: AVCaptureDevice.Position
	) -> Bool {
		switch mode {
		case .off: return false
		case .on: return true
		case .auto: return position == .front
		}
	}
}
#endif
