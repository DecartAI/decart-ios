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
					print("failed to update prompt: \(error.localizedDescription)")
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
	private var realtimeClient: RealtimeClient?
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
			print("error while switching camera!")
		}
	}

	func connect() async {
		do {
			realtimeClient = try decartClient
				.createRealtimeClient(options: RealtimeConfig(
					model: Models.realtime(.mirage),
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
				for await event in realtimeClient.events {
					if Task.isCancelled { return }
					await MainActor.run { [weak self] in
						guard let self = self else { return }

						switch event {
						case .stateChanged(let state):
							if state == .connected {
								Task.detached {
									try? await self.realtimeClient?
										.setPrompt(self.currentPrompt)
								}
							}
							print("🟢 Connection state changed: \(state)")
							self.connectionState = state

						case .error(let error):
							self.connectionState = .disconnected
							print("❌ Error received: \(error.localizedDescription)")
//							self.lastError = error.localizedDescription
						}
					}
				}
			}
			print("🔵 Connecting to WebRTC...")
			remoteMediaStreams = try await realtimeClient
				.connect(localStream: localMediaStream!)
		} catch {
			print("❌ Connection failed with error: \(error.localizedDescription)")
			print("❌ Error details: \(error)")
			await cleanup()
		}
	}

	func cleanup() async {
		print("🧼 Starting cleanup...")
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

		// 4. Clear the remote stream reference
		remoteMediaStreams = nil

		localMediaStream = nil
		// 5. Reset the connection state.
		// We are on the MainActor, so this is safe.
		connectionState = .idle

		print("✅ Cleanup complete.")
	}
}
