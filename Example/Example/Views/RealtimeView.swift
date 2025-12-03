import DecartSDK
import Factory
import SwiftUI
import WebRTC

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
					currentPrompt: Prompt(text: defaultPrompt, enrich: false)
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
			if realtimeManager.remoteMediaStreams != nil {
				RTCMLVideoViewWrapper(
					track: realtimeManager.remoteMediaStreams?.videoTrack,
					mirror: realtimeManager.shouldMirror
				)
				.background(Color.black)
				.edgesIgnoringSafeArea(.all)
			}

			VStack(spacing: 5) {
				HStack {
					VStack(alignment: .center, spacing: 1) {
						Text(realtimeManager.connectionState.rawValue)
							.font(.caption)
							.foregroundColor(
								realtimeManager.connectionState.isConnected ? .green : .white
							)
					}
					Spacer()
				}
				.padding(.bottom, 10)
				.background(Color.black.opacity(0.6))

				Spacer()

				if realtimeManager.connectionState.isInSession,
				   let localStream = realtimeManager.localMediaStream
				{
					DraggableRTCVideoView(
						track: localStream.videoTrack,
						mirror: realtimeManager.shouldMirror
					)
				}

				RealtimeControlsView(
					presets: presets,
					connectionState: realtimeManager.connectionState,
					onPresetSelected: { preset in
						realtimeManager.currentPrompt = Prompt(text: preset.prompt, enrich: false)
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
