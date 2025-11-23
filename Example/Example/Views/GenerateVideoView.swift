//
//  GenerateVideoView.swift
//  Example
//
//  Created by Alon Bar-el on 23/11/2025.
//

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
	@State private var selectedMediaData: Data?
	@State private var selectedMediaType: UTType?
	@State private var generatedVideoURL: URL?
	@State private var isProcessing = false
	@State private var errorMessage: String?

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
		let hasAttachment = !requiresAttachment || selectedMediaData != nil
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
			ScrollView {
				resultSection
					.padding(.horizontal)
					.padding(.top)
			}

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
			if let url = generatedVideoURL {
				VideoPlayer(player: AVPlayer(url: url))
					.frame(height: 280)
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
							? "Describe your clip and attach a reference."
							: "Describe the motion you'd like."
					)
				)
				.padding(.vertical, 24)
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
			if let preview = selectedMediaData {
				attachmentPreview(data: preview)
			}

			TextField("Enter prompt…", text: $prompt, axis: .vertical)
				.lineLimit(1 ... 3)
				.textFieldStyle(.roundedBorder)
				.disabled(isProcessing)

			HStack(spacing: 12) {
				if requiresAttachment {
					PhotosPicker(selection: $selectedItem, matching: pickerFilter) {
						Label("Attach", systemImage: "paperclip")
					}
					.onChange(of: selectedItem) { newItem in
						loadSelectedMedia(from: newItem)
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

	func attachmentPreview(data: Data) -> some View {
		return HStack {
			if selectedMediaType?.conforms(to: .image) == true, let image = UIImage(data: data) {
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

	private func loadSelectedMedia(from item: PhotosPickerItem?) {
		guard let item else {
			clearAttachment()
			return
		}

		Task {
			do {
				if let data = try await item.loadTransferable(type: Data.self) {
					let type =
						item.supportedContentTypes.first(where: { $0.conforms(to: .video) || $0.conforms(to: .image) })
							?? item.supportedContentTypes.first

					await MainActor.run {
						selectedMediaData = data
						selectedMediaType = type
					}
				}
			} catch {
				await MainActor.run {
					errorMessage = error.localizedDescription
				}
			}
		}
	}

	private func generate() {
		let promptText = trimmedPrompt
		guard !promptText.isEmpty else { return }

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
					guard let data = selectedMediaData else {
						throw DecartError.invalidInput("Please attach an image first")
					}
					let fileInput = makeFileInput(from: data, type: selectedMediaType)
					let input = ImageToVideoInput(prompt: promptText, data: fileInput)
					processClient = try decartClient.createProcessClient(model: model, input: input)

				case .videoToVideo:
					guard let data = selectedMediaData else {
						throw DecartError.invalidInput("Please attach a video first")
					}
					let fileInput = makeFileInput(from: data, type: selectedMediaType)
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
				}
			} catch {
				await MainActor.run {
					errorMessage = error.localizedDescription
				}
			}

			await MainActor.run {
				isProcessing = false
			}
		}
	}

	private func makeFileInput(from data: Data, type: UTType?) -> FileInput {
		let ext: String
		if let preferred = type?.preferredFilenameExtension, !preferred.isEmpty {
			ext = preferred
		} else if type?.conforms(to: .image) == true {
			ext = "jpg"
		} else if type?.conforms(to: .video) == true {
			ext = "mp4"
		} else {
			ext = "bin"
		}

		let filename = "attachment.\(ext)"
		return FileInput(data: data, filename: filename)
	}

	private func clearAttachment() {
		selectedItem = nil
		selectedMediaData = nil
		selectedMediaType = nil
	}
}

#Preview {
	NavigationView {
		GenerateVideoView(model: .lucy_pro_t2v)
	}
}
