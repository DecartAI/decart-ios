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
	static let apiKey = "realtime-test_cvXwtMYGLstCYcYALueGFfzMUmYXUaRTYUEoPvEVoFBqfeQvUZitXstIRdxNFzMM"
	static let baseURL = "https://api3.decart.ai"
	static let defaultPrompt = "Turn the figure into a fantasy figure"
}

struct ContentView: View {
	private let decartClientManager: DecartClientManager?
	init() {
		do {
			decartClientManager = try .init(
				configuration: DecartConfiguration(
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
		if let manager = decartClientManager {
			NavigationView {
				List {
					NavigationLink(destination: RealtimeView(decartClientManager: manager)) {
						Text("Realtime")
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
	let decartClientManager: DecartClientManager
	@State private var prompt: String = Config.defaultPrompt

	@State private var viewModel: RealtimeManager

	init(decartClientManager: DecartClientManager) {
		self.decartClientManager = decartClientManager
		_viewModel = State(
			initialValue: RealtimeManager(
				decartClientManager: decartClientManager,
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
			// Remote video background

			// UI overlay
			VStack(spacing: 16) {
				// Top bar
				HStack {
					VStack(alignment: .leading, spacing: 4) {
						Text("Decart Realtime")
							.font(.headline)
							.foregroundColor(.white)
						Text(viewModel.connectionState.rawValue)
							.font(.caption)
							.foregroundColor(
								viewModel.connectionState.isConnected ? .green : .white
							)
					}
					Spacer()
				}
				.padding()
				.background(Color.black.opacity(0.6))

				Spacer()

				// Local video preview
				if viewModel.connectionState.isInSession, viewModel.localMediaStream != nil {
					HStack {
						Spacer()
						RTCMLVideoViewWrapper(
							track: viewModel.localMediaStream!.videoTrack
						)
						.frame(width: 120, height: 160)
						.cornerRadius(12)
						.overlay(
							RoundedRectangle(cornerRadius: 12).stroke(Color.white, lineWidth: 2)
						)
						.padding()
					}
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
						Toggle("Mirror", isOn: $viewModel.isMirroringEnabled)
							.toggleStyle(SwitchToggleStyle(tint: .blue))
						// .disabled(!viewModel.isConnected)

						Spacer()

						Button(action: {
							if viewModel.connectionState.isInSession {
								Task {
									await viewModel.cleanup()
								}
							} else {
								Task {
									try? await viewModel.connect()
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
				.padding()
				.onDisappear { Task { await viewModel.cleanup() } }
			}
		}
	}
}
