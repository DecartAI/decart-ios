import DecartSDK
import Factory
import SwiftUI

struct RealtimeView: View {
	private let realtimeAiModel: RealtimeModel
	private let presets: [PromptPreset]
	@State private var realtimeManager: RealtimeManager?

	init(realtimeModel: RealtimeModel) {
		self.realtimeAiModel = realtimeModel
		self.presets = DecartConfig.presets(for: realtimeModel)
	}

	var body: some View {
		ZStack {
			if let manager = realtimeManager {
				RealtimeContentView(
					realtimeManager: manager,
					presets: presets
				)
			} else {
				ProgressView("Loading...")
			}
		}
		.onAppear {
			if realtimeManager == nil {
				let defaultPrompt = presets.first?.prompt ?? ""
				realtimeManager = RealtimeManager(
					model: realtimeAiModel,
					currentPrompt: DecartPrompt(text: defaultPrompt, enrich: false)
				)
				Task {
					await realtimeManager?.connect()
				}
			}
		}
		.onDisappear {
			Task { [realtimeManager] in
				await realtimeManager?.cleanup()
			}
			realtimeManager = nil
		}
	}
}

private struct RealtimeContentView: View {
	@Bindable var realtimeManager: RealtimeManager
	let presets: [PromptPreset]

	var body: some View {
		ZStack {
			if let remoteVideoTrack = realtimeManager.remoteMediaStreams?.videoTrack {
				RTCMLVideoViewWrapper(
					track: remoteVideoTrack
				)
				.background(Color.black)
				.edgesIgnoringSafeArea(.all)
			} else {
				Color.black
					.edgesIgnoringSafeArea(.all)
			}

			VStack(spacing: 5) {
				HStack(alignment: .top) {
					VStack(alignment: .leading, spacing: 6) {
						Text(realtimeManager.connectionState.rawValue)
							.font(.caption)
							.foregroundColor(
								realtimeManager.connectionState.isConnected ? .green : .white
							)
						if let quality = realtimeManager.connectionQuality {
							ConnectionQualityBadge(report: quality)
						}
					}
					Spacer()
					ConnectivityPreflightView(
						isChecking: realtimeManager.isCheckingConnectivity,
						report: realtimeManager.connectivityReport,
						debugQuality: realtimeManager.debugQualityEnabled,
						onCheck: { Task { await realtimeManager.checkConnectivity() } },
						onDeepProbe: { Task { await realtimeManager.runDeepProbe() } },
						onToggleDebugQuality: { on in Task { await realtimeManager.setDebugQuality(on) } }
					)
					.frame(maxWidth: 260, alignment: .trailing)
				}
				.padding(.horizontal, 12)
				.padding(.top, 8)
				.padding(.bottom, 10)
				.background(Color.black.opacity(0.6))

				Spacer()

				if realtimeManager.connectionState.isInSession,
				   let localStream = realtimeManager.localMediaStream
				{
					DraggableRTCVideoView(track: localStream.videoTrack)
				}

				RealtimeControlsView(
					presets: presets,
					connectionState: realtimeManager.connectionState,
					onPresetSelected: { preset in
						realtimeManager.currentPrompt = DecartPrompt(text: preset.prompt, enrich: false)
					},
					onSwitchCamera: { Task { await realtimeManager.switchCamera() } },
					onConnectToggle: {
						if realtimeManager.connectionState.isInSession {
							Task { await realtimeManager.cleanup() }
						} else {
							Task { await realtimeManager.connect() }
						}
					}
				)
			}
		}
	}
}
