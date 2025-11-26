//
//  CaptureUtils.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 05/11/2025.
//
import AVFoundation
@preconcurrency import WebRTC

#if !targetEnvironment(simulator)
public enum RealtimeCameraCapture {
	public static func captureLocalCameraStream(realtimeManager: RealtimeManager, cameraFacing: AVCaptureDevice.Position) async throws -> (
		RealtimeMediaStream,
		RTCCameraVideoCapturer
	) {
		let currentRealtimeModel = realtimeManager.options.model

		let videoSource = realtimeManager.createVideoSource()
		let capturer = RTCCameraVideoCapturer(delegate: videoSource)

		let device = try AVCaptureDevice.pickCamera(position: cameraFacing)
		let format = try device.pickFormat(
			minWidth: currentRealtimeModel.width,
			minHeight: currentRealtimeModel.height
		)
		let targetFPS = try device.pickFPS(for: format, preferred: currentRealtimeModel.fps)

		try await startCameraCapture(capturer: capturer, device: device, format: format, fps: targetFPS)

		let localVideoTrack = realtimeManager.createVideoTrack(
			source: videoSource,
			trackId: "video0"
		)

		return (
			RealtimeMediaStream(videoTrack: localVideoTrack, id: .localStream),
			capturer
		)
	}

	private static func startCameraCapture(
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

	@discardableResult
	public static func switchCamera(
		capturer: RTCCameraVideoCapturer,
		realtimeManager: RealtimeManager,
		newPosition: AVCaptureDevice.Position
	) async throws -> AVCaptureDevice.Position {
		let currentRealtimeModel = realtimeManager.options.model

		let newDevice = try AVCaptureDevice.pickCamera(position: newPosition)
		let format = try newDevice.pickFormat(
			minWidth: currentRealtimeModel.width,
			minHeight: currentRealtimeModel.height
		)
		let targetFPS = try newDevice.pickFPS(for: format, preferred: currentRealtimeModel.fps)

		try await startCameraCapture(
			capturer: capturer,
			device: newDevice,
			format: format,
			fps: targetFPS
		)

		return newPosition
	}
}
#endif
