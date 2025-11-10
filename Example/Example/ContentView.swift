//
//  ContentView.swift
//  Example
//
//  Created by Alon Bar-el on 03/11/2025.
//

import DecartSDK
import SwiftUI
import WebRTC

private enum Config {
	static let apiKey = "real_SneqRkuhyIRnMpXDLLrrNpCvkLZvlNiqpxtTJBxRnrerWQIOMtKkysNbOUKTuofs"
	static let baseURL = "https://api3.decart.ai"
	static let defaultPrompt = "Turn the figure into a fantasy figure"
}

struct ContentView: View {
	private let decartClient: DecartClient?
	init() {
		do {
			decartClient = try DecartClient(
				decartConfiguration: DecartConfiguration(
					baseURL: Config.baseURL,
					apiKey: Config.apiKey
				)
			)
		} catch {
			print("error initializing DecartClient \(error)")
			fatalError("Failed to initialize DecartClient--- \(error)")
		}
	}

	var body: some View {
		if let manager = decartClient {
			NavigationView {
				List(RealtimeModel.allCases, id: \.self) { model in
					NavigationLink(
						destination: RealtimeView(
							decartClient: manager,
							realtimeModel: model
						)
					) {
						Text("Realtime - \(model.rawValue.capitalized)")
					}
				}
				.navigationBarTitle("Example")
			}
		} else {
			VStack {
				Text("Failed to initialize DecartClient. Please check your API key and base URL.")
			}
		}
	}
}

struct RealtimeView: View {
	private let decartClient: DecartClient?
	private let realtimeModel: RealtimeModel
	@State private var prompt: String = Config.defaultPrompt

	@State private var viewModel: RealtimeManager

	init(decartClient: DecartClient, realtimeModel: RealtimeModel) {
		self.decartClient = decartClient
		self.realtimeModel = realtimeModel
		_viewModel = State(
			initialValue: DecartRealtimeManager(
				decartClient: decartClient,
				currentPrompt: Prompt(text: Config.defaultPrompt, enrich: false)
			)
		)
	}

	var body: some View {
		ZStack {
			if viewModel.remoteMediaStreams != nil {
				RTCMLVideoViewWrapper(
					track: viewModel.remoteMediaStreams?.videoTrack
				)
				.background(Color.black)
				.edgesIgnoringSafeArea(.all)
			}
			// UI overlay
			VStack(spacing: 5) {
				// Top bar
				HStack {
					VStack(alignment: .center, spacing: 1) {
						Text(viewModel.connectionState.rawValue)
							.font(.caption)
							.foregroundColor(
								viewModel.connectionState.isConnected ? .green : .white
							)
					}
					Spacer()
				}
				.padding(.bottom, 10)
				.background(Color.black.opacity(0.6))

				Spacer()

				// Local video preview
				if viewModel.connectionState.isInSession, viewModel.localMediaStream != nil {
					DraggableRTCVideoView(
						track: viewModel.localMediaStream!.videoTrack,
						mirror: viewModel.shouldMirror
					)
				}

				// Controls
				VStack(spacing: 12) {
					if viewModel.connectionState == .error {
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
						// .disabled(!viewModel.isConnected)

						Button(action: {
							Task {
								viewModel.currentPrompt = Prompt(text: prompt, enrich: false)
							}
						}) {
							Image(systemName: "paperplane.fill")
								.foregroundColor(.white)
								.padding(12)
								.background(
									viewModel.connectionState.isConnected ? Color.blue : Color.gray
								)
								.cornerRadius(8)
						}
						// .disabled(!viewModel.isConnected)
					}

					HStack(spacing: 12) {
						Toggle("Mirror", isOn: $viewModel.shouldMirror)
							.toggleStyle(SwitchToggleStyle(tint: .blue))
						// .disabled(!viewModel.isConnected)
						Button(action: {
							Task {
								await viewModel.switchCamera()
							}
						}) {
							Image(systemName: "arrow.trianglehead.2.counterclockwise.rotate.90")
						}
						Spacer()

						Button(action: {
							if viewModel.connectionState.isInSession {
								Task {
									await viewModel.cleanup()
								}
							} else {
								Task {
									await viewModel
										.connect(model: self.realtimeModel)
								}
							}
						}) {
							Text(
								viewModel.connectionState.rawValue
							)
							.fontWeight(.semibold)
							.foregroundColor(.white)
							.frame(maxWidth: .infinity)
							.padding()
							.background(
								viewModel.connectionState.isConnected ? Color.red : Color.green
							)
							.cornerRadius(12)
						}
					}
				}
				.padding()
				.background(Color.black.opacity(0.8))
				.cornerRadius(16)
				.padding(.all, 5)
				.onDisappear { Task { await viewModel.cleanup() } }
			}
		}
	}
}
