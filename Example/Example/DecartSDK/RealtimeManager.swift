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
			let prompt = currentPrompt
			Task { [weak self] in
				do {
					try await self?.realtimeManager?.setPrompt(prompt)
				} catch {
					DecartLogger.log("setPrompt failed: \(error.localizedDescription)", level: .error)
				}
			}
		}
	}

	private(set) var connectionState: DecartRealtimeConnectionState = .idle
	private(set) var localMediaStream: RealtimeMediaStream?
	private(set) var remoteMediaStreams: RealtimeMediaStream?

	/// Live in-session connection-quality verdict (nil until the first report).
	private(set) var connectionQuality: ConnectionQualityReport?
	/// Latest pre-connect connectivity probe result (nil until `checkConnectivity()` runs).
	private(set) var connectivityReport: ConnectivityReport?
	private(set) var isCheckingConnectivity = false
	/// Opt-in glass-to-glass measurement (visible marker, diagnostic). Reconnects on change.
	private(set) var debugQualityEnabled = false

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
	private var connectionQualityTask: Task<Void, Never>?

	@ObservationIgnored
	private var localVideoTrack: LocalVideoTrack?

	@ObservationIgnored
	private var mirrorProcessor: MirroringVideoProcessor?

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
					initialPrompt: currentPrompt,
					debugQuality: debugQualityEnabled
				)
			)

			guard let realtimeManager else {
				preconditionFailure("realtimeManager is nil after creation")
			}

			// Listen for connection state changes (connecting, connected, error, etc.)
			startEventMonitoring()
			startRemoteStreamMonitoring()
			startConnectionQualityMonitoring()

			#if !targetEnvironment(simulator)
			if debugQualityEnabled {
				// SDK-created stream carries the glass-to-glass stamp pipeline.
				let stream = decartClient.createLocalCameraStream(model: modelConfig, debugQuality: true)
				localMediaStream = stream
				localVideoTrack = stream.videoTrack as? LocalVideoTrack
			} else {
				startCapture(model: modelConfig)
			}

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

	/// SDK-only preflight: probe whether the network can sustain a session before
	/// connecting. Safe to call without a session (only hits public STUN).
	func checkConnectivity() async {
		guard !isCheckingConnectivity else { return }
		isCheckingConnectivity = true
		connectivityReport = nil
		defer { isCheckingConnectivity = false }
		connectivityReport = await decartClient.checkConnectivity()
	}

	/// Deep probe: briefly opens a real session with a synthetic source and measures
	/// true glass-to-glass latency (costs a short GPU session).
	func runDeepProbe() async {
		guard !isCheckingConnectivity else { return }
		isCheckingConnectivity = true
		connectivityReport = nil
		defer { isCheckingConnectivity = false }
		connectivityReport = await decartClient.checkConnectivity(
			options: .init(deep: true, model: Models.realtime(model))
		)
	}

	/// Toggle glass-to-glass measurement; reconnects if a session is live so the new
	/// setting takes effect (the stamp pipeline is wired at stream/connect time).
	func setDebugQuality(_ enabled: Bool) async {
		guard enabled != debugQualityEnabled else { return }
		debugQualityEnabled = enabled
		if connectionState.isInSession { await connect() }
	}

	func switchCamera() async {
		#if !targetEnvironment(simulator)
		guard let cameraCapturer = localVideoTrack?.capturer as? CameraCapturer else { return }
		do {
			try await cameraCapturer.switchCameraPosition()
			// Keep input-side mirroring (MirrorMode.auto) following the active camera,
			// whether the stream uses the mirror or the glass-to-glass stamp processor.
			let position = cameraCapturer.position
			switch cameraCapturer.processor {
			case let stamping as StampingVideoProcessor:
				stamping.cameraPosition = position
			case let mirroring as MirroringVideoProcessor:
				mirroring.cameraPosition = position
			default:
				break
			}
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

		connectionQualityTask?.cancel()
		connectionQualityTask = nil
		connectionQuality = nil

		try? await localVideoTrack?.stop()
		localVideoTrack = nil
		mirrorProcessor = nil

		// Close LiveKit connection and release server resources.
		await realtimeManager?.disconnect()
		realtimeManager = nil

		localMediaStream = nil
		remoteMediaStreams = nil
	}

	// MARK: - Private Helpers

	#if !targetEnvironment(simulator)
	private func startCapture(model: ModelDefinition) {
		let dimensions = Dimensions(width: Int32(model.width), height: Int32(model.height))
		let captureOptions = CameraCaptureOptions(
			position: .front,
			dimensions: dimensions,
			fps: model.fps
		)
		// .auto pre-flips the front camera so the server gets display-orientation
		// frames and server-baked content (e.g. watermarks) renders as-is.
		let processor = MirroringVideoProcessor(mode: .auto, cameraPosition: .front)
		mirrorProcessor = processor
		let videoTrack = LocalVideoTrack.createCameraTrack(
			name: "video0",
			options: captureOptions,
			processor: processor
		)
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

	private func startConnectionQualityMonitoring() {
		connectionQualityTask?.cancel()

		// Poll the live snapshot ~1 Hz so the badge's metrics (rtt/g2g/fps/drops) stay
		// fresh. The `connectionQualityUpdates` stream only fires on debounced level
		// changes, so its metrics would otherwise look fresh while going stale.
		connectionQualityTask = Task { [weak self] in
			while !Task.isCancelled {
				guard let self, let manager = self.realtimeManager else { return }
				self.connectionQuality = manager.getConnectionQuality()
				try? await Task.sleep(nanoseconds: 1_000_000_000)
			}
		}
	}
}
