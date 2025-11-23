//
//  GenerateVideoView.swift
//  Example
//
//  Created by Alon Bar-el on 23/11/2025.
//

import AVFoundation
import AVKit
import DecartSDK
import Factory
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct GenerateVideoView: View {
	let model: VideoModel

	@Injected(\.decartClient) private var decartClient

	@State private var prompt: String = ""
	@State private var selectedItem: PhotosPickerItem?
	@State private var selectedMediaPreview: UIImage?
	@State private var selectedMediaType: UTType?
	@State private var generatedVideoURL: URL?
	@State private var videoPlayer: AVPlayer?
	@State private var isProcessing = false
	@State private var errorMessage: String?
	@FocusState private var promptFocused: Bool

	private var trimmedPrompt: String {
		prompt.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private var inputType: ModelInputType {
		ModelsInputFactory.videoInputType(for: model)
	}

	private var requiresAttachment: Bool {
		inputType == .imageToVideo || inputType == .videoToVideo
	}

	private var canSend: Bool {
		let hasPrompt = !trimmedPrompt.isEmpty
		let hasAttachment = !requiresAttachment || selectedItem != nil
		return hasPrompt && hasAttachment && !isProcessing
	}

	private var pickerFilter: PHPickerFilter {
		switch inputType {
		case .imageToVideo:
			return .images
		case .videoToVideo:
			return .videos
		default:
			return .any(of: [.images, .videos])
		}
	}

	var body: some View {
		VStack(spacing: 16) {
			resultSection
				.padding(.horizontal)
				.padding(.top)
				.contentShape(Rectangle())
				.onTapGesture {
					dismissKeyboard()
				}
			Spacer()

			Divider()

			inputSection
				.padding(.horizontal)
				.padding(.bottom)
		}
		.navigationTitle(model.rawValue)
		.navigationBarTitleDisplayMode(.inline)
	}

	private var resultSection: some View {
		VStack(spacing: 12) {
			if let player = videoPlayer {
				VideoPlayer(player: player)
					.onAppear {
						Task {
							try? await Task.sleep(for: .milliseconds(500))  // or .seconds(0.5) [web:15][web:18][web:21]
							player.play()
						}
					}
					.frame(height: 380)
					.cornerRadius(12)
					.shadow(radius: 4)
			} else if isProcessing {
				ProgressView("Generating…")
					.padding()
			} else {
				ContentUnavailableView(
					"Ready to animate",
					systemImage: "video.badge.plus",
					description: Text(
						requiresAttachment
							? "Describe your clip and attach a reference media."
							: "Describe the motion you'd like."
					)
				)
				.padding(.vertical, 14)
			}

			if let errorMessage {
				Text(errorMessage)
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
	}

	private var inputSection: some View {
		VStack(spacing: 12) {
			if selectedItem != nil {
				attachmentPreview()
			}

			TextField("Enter prompt…", text: $prompt, axis: .vertical)
				.lineLimit(1...3)
				.textFieldStyle(.roundedBorder)
				.disabled(isProcessing)
				.focused($promptFocused)

			HStack(spacing: 12) {
				if requiresAttachment {
					PhotosPicker(selection: $selectedItem, matching: pickerFilter) {
						Label("Attach", systemImage: "paperclip")
					}
					.onChange(of: selectedItem) { newItem in
						handleSelectionChange(newItem)
					}
				}

				Spacer()

				Button(action: generate) {
					Image(systemName: "paperplane.fill")
						.foregroundColor(canSend ? .white : .gray)
						.padding(10)
						.background(canSend ? Color.accentColor : Color.gray.opacity(0.3))
						.clipShape(Circle())
				}
				.disabled(!canSend)
			}
		}
	}

	func attachmentPreview() -> some View {
		return HStack {
			if let image = selectedMediaPreview {
				Image(uiImage: image)
					.resizable()
					.scaledToFill()
					.frame(width: 64, height: 64)
					.clipShape(RoundedRectangle(cornerRadius: 8))
			} else {
				Image(systemName: "video.fill")
					.font(.title2)
					.frame(width: 64, height: 64)
					.background(Color.blue.opacity(0.15))
					.clipShape(RoundedRectangle(cornerRadius: 8))
					.foregroundColor(.blue)
			}

			Text("Attachment ready")
				.font(.subheadline)

			Spacer()

			Button {
				clearAttachment()
			} label: {
				Image(systemName: "xmark.circle.fill")
					.foregroundStyle(.secondary)
			}
		}
	}

	private func handleSelectionChange(_ item: PhotosPickerItem?) {
		guard let item else {
			selectedMediaPreview = nil
			selectedMediaType = nil
			return
		}

		Task {
			let resolvedType =
				item.supportedContentTypes.first(where: {
					$0.conforms(to: .video) || $0.conforms(to: .image)
				}) ?? item.supportedContentTypes.first

			var previewImage: UIImage?
			if resolvedType?.conforms(to: .image) == true,
				let data = try? await item.loadTransferable(type: Data.self),
				let image = UIImage(data: data)
			{
				previewImage = image
			}

			await MainActor.run {
				selectedMediaType = resolvedType
				selectedMediaPreview = previewImage
			}
		}
	}

	private func resolveMediaType(for item: PhotosPickerItem) -> UTType? {
		if let storedType = selectedMediaType {
			return storedType
		}

		return item.supportedContentTypes.first(where: {
			$0.conforms(to: .video) || $0.conforms(to: .image)
		}) ?? item.supportedContentTypes.first
	}

	private func generate() {
		let promptText = trimmedPrompt
		guard !promptText.isEmpty else { return }
		dismissKeyboard()

		isProcessing = true
		errorMessage = nil
		generatedVideoURL = nil

		Task {
			do {
				let processClient: ProcessClient

				switch inputType {
				case .textToVideo:
					let input = TextToVideoInput(prompt: promptText)
					processClient = try decartClient.createProcessClient(model: model, input: input)

				case .imageToVideo:
					guard let selection = selectedItem else {
						throw DecartError.invalidInput("Please attach an image first")
					}
					guard let data = try await selection.loadTransferable(type: Data.self) else {
						throw DecartError.invalidInput("Failed to load selected image")
					}
					guard let mediaType = resolveMediaType(for: selection) else {
						throw DecartError.invalidInput("Unsupported media type")
					}
					let fileInput = try FileInput.from(
						data: data,
						uniformType: mediaType
					)
					let input = ImageToVideoInput(prompt: promptText, data: fileInput)
					processClient = try decartClient.createProcessClient(model: model, input: input)

				case .videoToVideo:
					guard let selection = selectedItem else {
						throw DecartError.invalidInput("Please attach a video first")
					}
					guard let data = try await selection.loadTransferable(type: Data.self) else {
						throw DecartError.invalidInput("Failed to load selected video")
					}
					guard let mediaType = resolveMediaType(for: selection) else {
						throw DecartError.invalidInput("Unsupported media type")
					}
					let fileInput = try FileInput.from(
						data: data,
						uniformType: mediaType
					)
					let input = VideoToVideoInput(prompt: promptText, data: fileInput)
					processClient = try decartClient.createProcessClient(model: model, input: input)

				default:
					throw DecartError.invalidInput("Unsupported input type")
				}

				let data = try await processClient.process()
				let tempURL = FileManager.default.temporaryDirectory
					.appendingPathComponent(UUID().uuidString)
					.appendingPathExtension("mp4")
				try data.write(to: tempURL, options: .atomic)

				await MainActor.run {
					generatedVideoURL = tempURL
					let player = AVPlayer(url: tempURL)
					videoPlayer = player
				}
			} catch {
				await MainActor.run {
					errorMessage = error.localizedDescription
				}
			}

			await MainActor.run {
				isProcessing = false
				dismissKeyboard()
			}
		}
	}

	private func clearAttachment() {
		selectedItem = nil
		selectedMediaPreview = nil
		selectedMediaType = nil
		dismissKeyboard()
	}

	private func dismissKeyboard() {
		withAnimation(.linear(duration: 0.5)) {
			promptFocused = false
		}
	}
}

#Preview {
	NavigationView {
		GenerateVideoView(model: .lucy_pro_t2v)
	}
}
