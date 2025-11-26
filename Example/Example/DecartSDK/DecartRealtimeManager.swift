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
@preconcurrency import WebRTC

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
	#if !targetEnvironment(simulator)
	@ObservationIgnored
	private var capture: RealtimeCapture?
	#endif
	@ObservationIgnored
	private var eventTask: Task<Void, Never>?

	init(
		currentPrompt: Prompt,
		isMirroringEnabled: Bool = true
	) {
		self.currentPrompt = currentPrompt
		self.shouldMirror = isMirroringEnabled
	}

	func switchCamera() async {
		#if !targetEnvironment(simulator)
		guard let capture else { return }
		do {
			try await capture.switchCamera()
			shouldMirror = capture.position == .front
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
			let modelConfig = Models.realtime(model)
			realtimeManager =
				try decartClient
					.createRealtimeManager(
						options: RealtimeConfiguration(
							model: modelConfig,
							initialState: ModelState(
								prompt: currentPrompt
							)
						))
			guard let realtimeManager else {
				preconditionFailure("realtimeManager is nil after creating it")
			}

			monitorEvents()

			#if !targetEnvironment(simulator)
			let videoSource = realtimeManager.createVideoSource()
			capture = RealtimeCapture(model: modelConfig, videoSource: videoSource)
			try await capture?.startCapture()

			let localVideoTrack = realtimeManager.createVideoTrack(source: videoSource, trackId: "video0")
			localMediaStream = RealtimeMediaStream(videoTrack: localVideoTrack, id: .localStream)

			remoteMediaStreams = try await realtimeManager.connect(localStream: localMediaStream!)
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
				}
			}
			DecartLogger.log("Event monitoring task completed.", level: .info)
		}
	}

	func cleanup() async {
		connectionState = .idle
		try? await Task.sleep(nanoseconds: 100_000_000)

		eventTask?.cancel()
		eventTask = nil

		localMediaStream?.videoTrack.isEnabled = false
		localMediaStream?.audioTrack?.isEnabled = false
		remoteMediaStreams?.videoTrack.isEnabled = false
		remoteMediaStreams?.audioTrack?.isEnabled = false

		#if !targetEnvironment(simulator)
		await capture?.stopCapture()
		capture = nil
		#endif

		await realtimeManager?.disconnect()
		realtimeManager = nil

		localMediaStream = nil
		remoteMediaStreams = nil
	}
}
