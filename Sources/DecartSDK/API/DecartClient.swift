import AVFoundation
import Foundation
@preconcurrency import LiveKit

public struct DecartClient: Sendable {
	let decartConfiguration: DecartConfiguration

	public init(decartConfiguration: DecartConfiguration) {
		self.decartConfiguration = decartConfiguration
	}

	public func createRealtimeManager(options: RealtimeConfiguration) throws -> DecartRealtimeManager {
		var urlString =
			"\(decartConfiguration.signalingServerUrl)\(options.model.urlPath)?api_key=\(decartConfiguration.apiKey)&model=\(options.model.name)"

		if let resolution = options.resolution {
			urlString += "&resolution=\(resolution.rawValue)"
		}

		// Ask the server to re-stamp the pixel marker from input to output so the
		// client can read glass-to-glass latency back off the rendered frames.
		if options.debugQuality {
			urlString += "&pixel_latency=1"
		}

		guard let signalingServerURL = URL(string: urlString) else {
			DecartLogger.log("Unable to generate signaling server URL from: \(urlString)", level: .error)
			throw DecartError.invalidBaseURL(urlString)
		}

		return DecartRealtimeManager(
			signalingServerURL: signalingServerURL,
			options: options
		)
	}

	/// Build a camera-backed local stream sized for `model`, ready to pass to
	/// `DecartRealtimeManager.connect(localStream:)`.
	///
	/// When `debugQuality` is true the stream carries the glass-to-glass stamp
	/// pipeline (a visible pixel marker stamped into each outgoing frame) — pair it
	/// with `RealtimeConfiguration(debugQuality: true)`. Diagnostic only. Otherwise
	/// the stream just mirrors the front camera per `mirror`.
	@MainActor
	public func createLocalCameraStream(
		model: ModelDefinition,
		position: AVCaptureDevice.Position = .front,
		mirror: MirrorMode = .auto,
		debugQuality: Bool = false
	) -> RealtimeMediaStream {
		let dimensions = Dimensions(width: Int32(model.width), height: Int32(model.height))
		let captureOptions = CameraCaptureOptions(position: position, dimensions: dimensions, fps: model.fps)

		let tracker = debugQuality ? SeqTracker() : nil
		let processor: VideoProcessor?
		if let tracker {
			processor = StampingVideoProcessor(mode: mirror, cameraPosition: position, tracker: tracker)
		} else {
			processor = MirroringVideoProcessor(mode: mirror, cameraPosition: position)
		}

		let videoTrack = LocalVideoTrack.createCameraTrack(
			name: "video0",
			options: captureOptions,
			processor: processor
		)

		var stream = RealtimeMediaStream(videoTrack: videoTrack, id: .localStream)
		stream.seqTracker = tracker
		return stream
	}

	public func createProcessClient(
		model: ImageModel,
		input: ImageToImageInput,
		session: URLSession = .shared
	) throws -> ProcessClient {
		try ProcessClient(
			configuration: decartConfiguration,
			model: model,
			input: input,
			session: session
		)
	}

	public var queue: QueueClient {
		QueueClient(baseURL: decartConfiguration.baseURL, apiKey: decartConfiguration.apiKey)
	}
}
