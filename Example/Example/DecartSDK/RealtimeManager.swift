//
//  DecartRealtimeManager.swift
//  Example
//
//  Created by Alon Bar-el on 04/11/2025.
//
import Combine
import DecartSDK
import Factory
import AVFoundation
@preconcurrency import LiveKit
import SwiftUI

@MainActor
@Observable
final class RealtimeManager: RealtimeManagerProtocol {
	// MARK: - Public State

	var currentPrompt: DecartPrompt {
		didSet {
			// Send updated prompt to the server for real-time style changes
			realtimeManager?.setPrompt(currentPrompt)
		}
	}

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

	@ObservationIgnored
	private var remoteStreamTask: Task<Void, Never>?

	@ObservationIgnored
	private var localVideoTrack: LocalVideoTrack?

	// MARK: - Init

	init(model: RealtimeModel, currentPrompt: DecartPrompt) {
		self.model = model
		self.currentPrompt = currentPrompt
	}

	// MARK: - Public API

	func connect() async {
		if connectionState.isInSession || realtimeManager != nil {
			await cleanup()
		}

		connectionState = .connecting

		do {
			let modelConfig = Models.realtime(model)

			// Initialize the realtime manager with model config and initial prompt.
			realtimeManager = try decartClient.createRealtimeManager(
				options: RealtimeConfiguration(
					model: modelConfig,
					initialPrompt: currentPrompt
				)
			)

			guard let realtimeManager else {
				preconditionFailure("realtimeManager is nil after creation")
			}

			// Listen for connection state changes (connecting, connected, error, etc.)
			startEventMonitoring()
			startRemoteStreamMonitoring()

			#if !targetEnvironment(simulator)
			startCapture(model: modelConfig)

			// Establish LiveKit connection - sends local video, receives AI-processed video.
			let initialRemoteStream = try await realtimeManager.connect(localStream: localMediaStream!)
			if initialRemoteStream.videoTrack != nil {
				remoteMediaStreams = initialRemoteStream
			}
			#endif
		} catch {
			DecartLogger.log("Connection failed: \(error.localizedDescription)", level: .error)
			await cleanup()
		}
	}

	func switchCamera() async {
		#if !targetEnvironment(simulator)
		guard let cameraCapturer = localVideoTrack?.capturer as? CameraCapturer else { return }
		do {
			try await cameraCapturer.switchCameraPosition()
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

		remoteStreamTask?.cancel()
		remoteStreamTask = nil

		try? await localVideoTrack?.stop()
		localVideoTrack = nil

		// Close LiveKit connection and release server resources.
		await realtimeManager?.disconnect()
		realtimeManager = nil

		localMediaStream = nil
		remoteMediaStreams = nil
	}

	// MARK: - Private Helpers

	#if !targetEnvironment(simulator)
	private func startCapture(model: ModelDefinition) {
		let dimensions = Dimensions(width: Int32(model.height), height: Int32(model.width))
		let captureOptions = CameraCaptureOptions(
			position: .front,
			dimensions: dimensions,
			fps: model.fps
		)
		let videoTrack = LocalVideoTrack.createCameraTrack(name: "video0", options: captureOptions)
		localVideoTrack = videoTrack
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
				if state.connectionState == .error {
					// Treat signaling (WS) disconnects as disconnected in the example UI.
					self.connectionState = .error
				} else {
					self.connectionState = state.connectionState
				}
			}
		}
	}

	private func startRemoteStreamMonitoring() {
		remoteStreamTask?.cancel()

		remoteStreamTask = Task { [weak self] in
			guard let self, let stream = self.realtimeManager?.remoteStreamUpdates else { return }

			for await remoteStream in stream {
				if Task.isCancelled { return }
				guard remoteStream.videoTrack != nil else { continue }
				self.remoteMediaStreams = remoteStream
			}
		}
	}
}
