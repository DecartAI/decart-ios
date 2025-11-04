//
//  DecartClient.swift
//  Example
//
//  Created by Alon Bar-el on 04/11/2025.
//

import DecartSDK
import WebRTC

public struct DecartClientManager {
	let decartClient: DecartClient

	public init(
		configuration: DecartConfiguration
	) {
		self.decartClient = DecartClient(decartConfiguration: configuration)
	}
}

public extension DecartClientManager {
	func createRealtimeClient(realtimeConfig: RealtimeConfig) throws -> RealtimeClient {
		let realtimeClient = try decartClient.createRealtimeClient(
			options: realtimeConfig
		)
		return realtimeClient
	}

	func captureLocalCameraStream(realtimeClient: RealtimeClient) async throws -> (
		RealtimeMediaStream,
		RTCCameraVideoCapturer
	) {
		let currentRealtimeModel = realtimeClient.options.model
		#if targetEnvironment(simulator)
		throw CameraError.simulatorUnsupported
		#else
		// 1) Source & capturer
		let videoSource = realtimeClient.createVideoSource()
		let capturer = RTCCameraVideoCapturer(delegate: videoSource)
		#endif
		let device = try AVCaptureDevice.frontCamera()
		let format = try device.pickFormat(
			minWidth: currentRealtimeModel.width,
			minHeight: currentRealtimeModel.height
		)
		let targetFPS = try device.pickFPS(for: format, preferred: currentRealtimeModel.fps)

		// 3) Start capture
		try await startCapture(capturer: capturer, device: device, format: format, fps: targetFPS)
		let localVideoTrack = realtimeClient.createLocalVideoTrack(
			with: videoSource,
			trackId: "video0",
			enabled: true
		)
		// 4) Create track & stream
		return (
			RealtimeMediaStream(videoTrack: localVideoTrack, id: .localStream),
			capturer
		)
	}

	private func startCapture(
		capturer: RTCCameraVideoCapturer,
		device: AVCaptureDevice,
		format: AVCaptureDevice.Format,
		fps: Int
	) async throws {
		try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
			capturer.startCapture(with: device, format: format, fps: fps) { error in
				if let error { cont.resume(throwing: error) }
				else { cont.resume() }
			}
		}
	}
}

protocol DecartRealtimeManager {
	/// current realtimeClient from DecartClient
	var decartClientManager: DecartClientManager { get }
	/// the recent prompt that was sent to the model
	var currentPrompt: Prompt { get set }
	var isMirroringEnabled: Bool { get set }

	var connectionState: DecartRealtimeConnectionState { get }

	var localMediaStream: RealtimeMediaStream? { get }
	var remoteMediaStreams: RealtimeMediaStream? { get }

	func connect() async throws

	func cleanup() async throws

//	func createRealtimeClient(
//		options: RealtimeConfig
//	) throws -> RealtimeClient
//
//	func captureLocalCameraStream() async throws -> (
//		RealtimeMediaStream,
//		RTCCameraVideoCapturer
//	)
}
