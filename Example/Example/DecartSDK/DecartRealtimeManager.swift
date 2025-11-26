//
//  RealtimeManager.swift
//  Example
//
//  Created by Alon Bar-el on 04/11/2025.
//
import Combine
import DecartSDK
import Factory
import SwiftUI
import WebRTC

@MainActor
@Observable
final class DecartRealtimeManager: RealtimeManagerProtocol {
	@ObservationIgnored
	private let decartClient = Container.shared.decartClient()

	var currentPrompt: Prompt {
		didSet {
			Task { [weak self] in
				guard let self, let manager = self.realtimeManager else { return }
				manager.setPrompt(currentPrompt)
			}
		}
	}

	var shouldMirror: Bool

	private(set) var connectionState: DecartRealtimeConnectionState = .idle

	private(set) var localMediaStream: RealtimeMediaStream?

	private(set) var remoteMediaStreams: RealtimeMediaStream?

	@ObservationIgnored
	private var realtimeManager: RealtimeManager?
	@ObservationIgnored
	private var videoCapturer: RTCCameraVideoCapturer?
	@ObservationIgnored
	private var eventTask: Task<Void, Never>?

	init(
		currentPrompt: Prompt,
		isMirroringEnabled: Bool = true // since the initial camera is the front facing one
	) {
		self.currentPrompt = currentPrompt
		self.shouldMirror = isMirroringEnabled
	}

	func switchCamera() async {
		#if !targetEnvironment(simulator)
		print("switching camera to \(shouldMirror ? "back" : "front") camera")
		guard let videoCapturer, let realtimeManager else {
			preconditionFailure("🚨 videoCapturer is nil when switching camera")
		}
		do {
			try await RealtimeCameraCapture.switchCamera(
				capturer: videoCapturer,
				realtimeManager: realtimeManager,
				newPosition: shouldMirror ? .back : .front
			)
			shouldMirror.toggle()
		} catch {
			DecartLogger.log("error while switching camera!", level: .error)
		}
		#endif
	}

	func connect(model: RealtimeModel) async {
		if connectionState.isInSession || realtimeManager != nil {
			await cleanup()
		}

		connectionState = .connecting

		do {
			realtimeManager =
				try decartClient
					.createRealtimeManager(
						options: RealtimeConfiguration(
							model: Models.realtime(model),
							initialState: ModelState(
								prompt: currentPrompt
							)
						))
			guard let realtimeManager else {
				preconditionFailure("🚨 realtimeManager is nil after creating it")
			}

			monitorEvents()

			#if !targetEnvironment(simulator)
			(localMediaStream, videoCapturer) =
				try await RealtimeCameraCapture
					.captureLocalCameraStream(
						realtimeManager: realtimeManager,
						cameraFacing: .front
					)

			DecartLogger.log("Connecting to WebRTC...", level: .info)
			remoteMediaStreams =
				try await realtimeManager
					.connect(localStream: localMediaStream!)
			#endif
		} catch {
			DecartLogger.log(
				"Connection failed with error: \(error.localizedDescription)", level: .error
			)
			DecartLogger.log("Error details: \(error)", level: .error)
			await cleanup()
		}
	}

	private func monitorEvents() {
		eventTask?.cancel()

		eventTask = Task { [weak self] in
			guard let self, let stream = self.realtimeManager?.events else { return }

			for await state in stream {
				if Task.isCancelled { return }

				DecartLogger.log("Connection state changed: \(state)", level: .info)
				self.connectionState = state

				if state == .error {
					DecartLogger.log("Error state received", level: .error)
					// Should we disconnect on error? The connection might already be broken.
					// Cleanup handles it if needed, or we can just stay in error state.
					// For now, just updating state is enough as UI reacts to it.
				}
			}
		}
	}

	func cleanup() async {
		DecartLogger.log("Starting cleanup...", level: .info)
		eventTask?.cancel()
		eventTask = nil

		if let capturer = videoCapturer {
			await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
				capturer.stopCapture { k.resume() }
			}
		}
		videoCapturer = nil
		await realtimeManager?.disconnect()
		realtimeManager = nil
		remoteMediaStreams = nil
		localMediaStream = nil
		connectionState = .idle

		DecartLogger.log("Cleanup complete.", level: .success)
	}
}
