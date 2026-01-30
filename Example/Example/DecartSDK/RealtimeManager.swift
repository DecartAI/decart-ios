//
//  DecartRealtimeManager.swift
//  Example
//
//  Created by Alon Bar-el on 04/11/2025.
//
import Combine
import DecartSDK
import Factory
import SwiftUI
@preconcurrency import WebRTC

@MainActor
@Observable
final class RealtimeManager: RealtimeManagerProtocol {
	// MARK: - Public State

	var currentPrompt: Prompt {
		didSet {
			// Send updated prompt to the server for real-time style changes
			realtimeManager?.setPrompt(currentPrompt)
		}
	}

	var shouldMirror: Bool

	private(set) var connectionState: DecartRealtimeConnectionState = .idle
	private(set) var localMediaStream: RealtimeMediaStream?
	private(set) var remoteMediaStreams: RealtimeMediaStream?

	// MARK: - Private

	@ObservationIgnored
	private let decartClient = Container.shared.decartClient()

	@ObservationIgnored
	private let model: RealtimeModel

	@ObservationIgnored
	private var realtimeManager: DecartRealtimeManager?

	@ObservationIgnored
	private var eventTask: Task<Void, Never>?

	#if !targetEnvironment(simulator)
	@ObservationIgnored
	private var capture: RealtimeCapture?
	#endif

	// MARK: - Init

	init(model: RealtimeModel, currentPrompt: Prompt, isMirroringEnabled: Bool = true) {
		self.model = model
		self.currentPrompt = currentPrompt
		self.shouldMirror = isMirroringEnabled
	}

	// MARK: - Public API

	func connect() async {
		if connectionState.isInSession || realtimeManager != nil {
			await cleanup()
		}

		connectionState = .connecting

		do {
			let modelConfig = Models.realtime(model)

			// Initialize the WebRTC manager with model config and initial prompt
			realtimeManager = try decartClient.createRealtimeManager(
				options: RealtimeConfiguration(
					model: modelConfig,
					initialState: ModelState(prompt: currentPrompt)
				)
			)

			guard let realtimeManager else {
				preconditionFailure("realtimeManager is nil after creation")
			}

			// Listen for connection state changes (connecting, connected, error, etc.)
			startEventMonitoring()

			#if !targetEnvironment(simulator)
			try await startCapture(model: modelConfig)

			// Establish WebRTC connection - sends local video, receives AI-processed video
			remoteMediaStreams = try await realtimeManager.connect(localStream: localMediaStream!)
			#endif
		} catch {
			DecartLogger.log("Connection failed: \(error.localizedDescription)", level: .error)
			await cleanup()
		}
	}

	func switchCamera() async {
		#if !targetEnvironment(simulator)
		guard let capture else { return }
		do {
			// Toggle between front and back camera
			try await capture.switchCamera()
			shouldMirror = capture.position == .front
		} catch {
			DecartLogger.log("Failed to switch camera", level: .error)
		}
		#endif
	}

	func cleanup() async {
		connectionState = .idle

		// Brief delay to allow UI to update before teardown
		try? await Task.sleep(nanoseconds: 100_000_000)

		eventTask?.cancel()
		eventTask = nil

		disableMediaTracks()

		#if !targetEnvironment(simulator)
		// Release camera resources
		await capture?.stopCapture()
		capture = nil
		#endif

		// Close WebRTC connection and release server resources
		await realtimeManager?.disconnect()
		realtimeManager = nil

		localMediaStream = nil
		remoteMediaStreams = nil
	}

	// MARK: - Private Helpers

	#if !targetEnvironment(simulator)
	private func startCapture(model: ModelDefinition) async throws {
		guard let realtimeManager else { return }

		// Create a video source that camera frames will be written to
		let videoSource = realtimeManager.createVideoSource()

		// Initialize camera capture with model-specific settings (resolution, fps)
		capture = RealtimeCapture(model: model, videoSource: videoSource)
		try await capture?.startCapture()

		// Wrap the video source in a track for WebRTC transmission
		let videoTrack = realtimeManager.createVideoTrack(source: videoSource, trackId: "video0")
		localMediaStream = RealtimeMediaStream(videoTrack: videoTrack, id: .localStream)
	}
	#endif

	private func startEventMonitoring() {
		eventTask?.cancel()

		eventTask = Task { [weak self] in
			// Subscribe to connection state updates from the SDK
			guard let self, let stream = self.realtimeManager?.events else { return }

			for await state in stream {
				if Task.isCancelled { return }
				if state == .error {
					// Treat signaling (WS) disconnects as disconnected in the example UI.
					self.connectionState = .error
				} else {
					self.connectionState = state
				}
			}
		}
	}

	private func disableMediaTracks() {
		localMediaStream?.videoTrack.isEnabled = false
		localMediaStream?.audioTrack?.isEnabled = false
		remoteMediaStreams?.videoTrack.isEnabled = false
		remoteMediaStreams?.audioTrack?.isEnabled = false
	}
}
