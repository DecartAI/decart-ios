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
final class RealtimeManager: DecartRealtimeManager {
	var decartClientManager: DecartClientManager

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

	var isMirroringEnabled: Bool {
		didSet {
			Task { [weak self] in
				guard let self, self.connectionState == .connected else { return }
				do {
					try await self.realtimeClient?.setMirror(isMirroringEnabled)
				} catch {
					print("failed to update mirror: \(error.localizedDescription)")
				}
			}
		}
	}

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
		decartClientManager: DecartClientManager,
		currentPrompt: Prompt,
		isMirroringEnabled: Bool = false
	) {
		self.decartClientManager = decartClientManager
		self.currentPrompt = currentPrompt
		self.isMirroringEnabled = isMirroringEnabled
	}

	func connect() async throws {
		do {
			realtimeClient = try decartClientManager
				.createRealtimeClient(realtimeConfig: RealtimeConfig(
					model: Models.realtime(.mirage),
					initialState: ModelState(
						prompt: currentPrompt,
						mirror: isMirroringEnabled
					)
				))
			guard let realtimeClient else {
				preconditionFailure("🚨 realtimeClient is nil after creating it")
			}

			(localMediaStream, videoCapturer) = try await decartClientManager
				.captureLocalCameraStream(realtimeClient: realtimeClient)

			eventTask = Task { [weak self] in
				for await event in realtimeClient.events {
					await MainActor.run { [weak self] in
						guard let self = self else { return }

						switch event {
						case .remoteStreamReceived(let mediaStream):
							print("🟢 REMOTE STREAM RECEIVED!")

						case .stateChanged(let state):
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

		// 1. Stop listening for new events.
		// This is the first thing you should do, so you don't
		// process "disconnected" or "error" events while tearing down.
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

struct VideoView: UIViewRepresentable {
	var renderer: RTCMTLVideoView

	init(renderer: RTCMTLVideoView) {
		self.renderer = renderer
	}

	func makeUIView(context: Context) -> RTCMTLVideoView {
		return renderer
	}

	func updateUIView(_ renderer: RTCMTLVideoView, context: Context) {
		// do nothing
	}
}
