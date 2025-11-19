//
//  RealtimeManager.swift
//  Example
//
//  Created by Alon Bar-el on 04/11/2025.
//
import Combine
import DecartSDK
import SwiftUI
import WebRTC

@MainActor
@Observable
final class DecartRealtimeManager: RealtimeManager {
	let decartClient: DecartClient
	var currentPrompt: Prompt {
		didSet {
			Task { [weak self] in
				guard let self, let client = self.realtimeClient else { return }
				do {
					try await client.setPrompt(currentPrompt)
				} catch {
					DecartLogger.log("failed to update prompt: \(error.localizedDescription)", level: .error)
				}
			}
		}
	}

	var shouldMirror: Bool

	private(set) var connectionState: DecartRealtimeConnectionState = .idle

	@ObservationIgnored
	private(set) var localMediaStream: RealtimeMediaStream?
	@ObservationIgnored
	private(set) var remoteMediaStreams: RealtimeMediaStream?

	@ObservationIgnored
	private var realtimeClient: RealtimeEngine?
	@ObservationIgnored
	private var videoCapturer: RTCCameraVideoCapturer?
	@ObservationIgnored
	private var eventTask: Task<Void, Never>?

	init(
		decartClient: DecartClient,
		currentPrompt: Prompt,
		isMirroringEnabled: Bool = false
	) {
		self.decartClient = decartClient
		self.currentPrompt = currentPrompt
		self.shouldMirror = isMirroringEnabled
	}

	func switchCamera() async {
		guard let videoCapturer else {
			preconditionFailure("🚨 videoCapturer is nil when switching camera")
		}
		do {
			try await RealtimeCameraCapture.switchCamera(
				capturer: videoCapturer,
				realtimeClient: realtimeClient!,
				currentPosition: shouldMirror ? .back : .front
			)
			shouldMirror.toggle()
		} catch {
			DecartLogger.log("error while switching camera!", level: .error)
		}
	}

	func connect(model: RealtimeModel) async {
		do {
			realtimeClient = try decartClient
				.createRealtimeClient(options: RealtimeConfig(
					model: Models.realtime(model),
					initialState: ModelState(
						prompt: currentPrompt,
						mirror: shouldMirror
					)
				))
			guard let realtimeClient else {
				preconditionFailure("🚨 realtimeClient is nil after creating it")
			}

			(localMediaStream, videoCapturer) = try await RealtimeCameraCapture
				.captureLocalCameraStream(
					realtimeClient: realtimeClient,
					cameraFacing: .front
				)

			eventTask = Task { [weak self] in
				guard let stream = self?.realtimeClient?.events else { return }
				for await event in stream {
					if Task.isCancelled { return }
					guard let self else { return }

					switch event {
					case .stateChanged(let state):
						DecartLogger.log("Connection state changed: \(state)", level: .info)
						self.connectionState = state

					case .error(let error):
						self.connectionState = .disconnected
						DecartLogger.log("Error received: \(error.localizedDescription)", level: .error)
					}
				}
			}
			DecartLogger.log("Connecting to WebRTC...", level: .info)
			remoteMediaStreams = try await realtimeClient
				.connect(localStream: localMediaStream!)
		} catch {
			DecartLogger.log("Connection failed with error: \(error.localizedDescription)", level: .error)
			DecartLogger.log("Error details: \(error)", level: .error)
			await cleanup()
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
		await realtimeClient?.disconnect()
		realtimeClient = nil
		remoteMediaStreams = nil
		localMediaStream = nil
		connectionState = .idle

		DecartLogger.log("Cleanup complete.", level: .success)
	}
}
