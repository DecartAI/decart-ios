import DecartSDK
import Factory
import SwiftUI
import WebRTC

struct RealtimeView: View {
	private let realtimeAiModel: RealtimeModel
	@State private var prompt: String = DecartConfig.defaultPrompt
	@State private var realtimeManager: DecartRealtimeManager?

	init(realtimeModel: RealtimeModel) {
		self.realtimeAiModel = realtimeModel
	}

	var body: some View {
		ZStack {
			if let manager = realtimeManager {
				RealtimeContentView(
					realtimeManager: manager,
					realtimeAiModel: realtimeAiModel,
					prompt: $prompt
				)
			} else {
				ProgressView("Loading...")
			}
		}
		.onAppear {
			if realtimeManager == nil {
				realtimeManager = DecartRealtimeManager(
					currentPrompt: Prompt(text: DecartConfig.defaultPrompt, enrich: false)
				)
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
	@Bindable var realtimeManager: DecartRealtimeManager
	let realtimeAiModel: RealtimeModel
	@Binding var prompt: String

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

				VStack(spacing: 12) {
					if realtimeManager.connectionState == .error {
						Text("Error while connecting to decart realtime servers, please try again later.")
							.foregroundColor(.red)
							.font(.caption)
							.padding(8)
							.background(Color.black.opacity(0.8))
							.cornerRadius(8)
					}

					HStack(spacing: 12) {
						TextField("Prompt", text: $prompt)
							.textFieldStyle(RoundedBorderTextFieldStyle())

						Button(action: {
							realtimeManager.currentPrompt = Prompt(text: prompt, enrich: false)
						}) {
							Image(systemName: "paperplane.fill")
								.foregroundColor(.white)
								.padding(12)
								.background(
									realtimeManager.connectionState.isConnected
										? Color.blue : Color.gray
								)
								.cornerRadius(8)
						}
					}

					HStack(spacing: 12) {
						Toggle("Mirror", isOn: $realtimeManager.shouldMirror)
							.toggleStyle(SwitchToggleStyle(tint: .blue))

						Button(action: {
							Task { await realtimeManager.switchCamera() }
						}) {
							Image(systemName: "arrow.trianglehead.2.counterclockwise.rotate.90")
						}

						Spacer()

						Button(action: {
							if realtimeManager.connectionState.isInSession {
								Task { await realtimeManager.cleanup() }
							} else {
								Task { await realtimeManager.connect(model: realtimeAiModel) }
							}
						}) {
							Text(realtimeManager.connectionState.rawValue)
								.fontWeight(.semibold)
								.foregroundColor(.white)
								.frame(maxWidth: .infinity)
								.padding()
								.background(
									realtimeManager.connectionState.isConnected
										? Color.red : Color.green
								)
								.cornerRadius(12)
						}
					}
				}
				.padding()
				.background(Color.black.opacity(0.8))
				.cornerRadius(16)
				.padding(.all, 5)
			}
		}
	}
}
