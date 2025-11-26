//
//  RealtimeView.swift
//  Example
//
//  Created by Alon Bar-el on 19/11/2025.
//

import DecartSDK
import Factory
import SwiftUI
import WebRTC

struct RealtimeView: View {
	private let realtimeAiModel: RealtimeModel
	@State private var prompt: String = DecartConfig.defaultPrompt

	@State private var realtimeManager: RealtimeManagerProtocol

	init(realtimeModel: RealtimeModel) {
		self.realtimeAiModel = realtimeModel
		_realtimeManager = State(
			initialValue: DecartRealtimeManager(
				currentPrompt: Prompt(
					text: DecartConfig.defaultPrompt,
					enrich: false
				)
			)
		)
	}

	var body: some View {
		ZStack {
			if realtimeManager.remoteMediaStreams != nil {
				// we listen to shouldMirror here since the demo reflects the user camera.
				RTCMLVideoViewWrapper(
					track: realtimeManager.remoteMediaStreams?.videoTrack,
					mirror: realtimeManager.shouldMirror
				)
				.background(Color.black)
				.edgesIgnoringSafeArea(.all)
			}
			// UI overlay
			VStack(spacing: 5) {
				// Top bar
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

				// Local video preview
				if realtimeManager.connectionState.isInSession,
				   realtimeManager.localMediaStream != nil
				{
					DraggableRTCVideoView(
						track: realtimeManager.localMediaStream!.videoTrack,
						mirror: realtimeManager.shouldMirror
					)
				}

				// Controls
				VStack(spacing: 12) {
					if realtimeManager.connectionState == .error {
						Text(
							"Error while connecting to decart realtime servers, please try again later."
						)
						.foregroundColor(.red)
						.font(.caption)
						.padding(8)
						.background(Color.black.opacity(0.8))
						.cornerRadius(8)
					}

					HStack(spacing: 12) {
						TextField("Prompt", text: $prompt)
							.textFieldStyle(RoundedBorderTextFieldStyle())
						// .disabled(!viewModel.isConnected)

						Button(action: {
							Task {
								realtimeManager.currentPrompt = Prompt(text: prompt, enrich: false)
							}
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
						// .disabled(!viewModel.isConnected)
					}

					HStack(spacing: 12) {
						Toggle("Mirror", isOn: $realtimeManager.shouldMirror)
							.toggleStyle(SwitchToggleStyle(tint: .blue))
						// .disabled(!viewModel.isConnected)
						Button(action: {
							Task {
								await realtimeManager.switchCamera()
							}
						}) {
							Image(systemName: "arrow.trianglehead.2.counterclockwise.rotate.90")
						}
						Spacer()

						Button(action: {
							if realtimeManager.connectionState.isInSession {
								Task {
									await realtimeManager.cleanup()
								}
							} else {
								let model = self.realtimeAiModel // Capture value
								Task {
									await realtimeManager.connect(model: model)
								}
							}
						}) {
							Text(
								realtimeManager.connectionState.rawValue
							)
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
				.onDisappear {
					Task { [realtimeManager] in
						await realtimeManager.cleanup()
					}
				}
			}
		}
	}
}
