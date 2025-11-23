//
//  GenerateVideoView.swift
//  Example
//
//  Created by Alon Bar-el on 23/11/2025.
//

import AVFoundation
import AVKit
import DecartSDK
import PhotosUI
import SwiftUI

struct GenerateVideoView: View {
	let model: VideoModel
	@State private var videoFetcher = VideoFetcher()
	@State private var selectedItem: PhotosPickerItem?
	@State private var selectedMediaPreview: UIImage?
	@FocusState private var promptFocused: Bool

	private var trimmedPrompt: String {
		videoFetcher.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
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
		return hasPrompt && hasAttachment && !videoFetcher.isProcessing
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
		.onDisappear {
			videoFetcher.cancelGeneration()
			videoFetcher.reset()
		}
		.navigationTitle(model.rawValue)
		.navigationBarTitleDisplayMode(.inline)
	}

	private var resultSection: some View {
		VStack(spacing: 12) {
			if videoFetcher.isProcessing {
				ProgressView("Generating…")
					.padding()
			} else if let player = videoFetcher.videoPlayer {
				VideoPlayer(player: player)
					.onAppear {
						player.play()
					}
					.onDisappear {
						player.pause()
					}
					.frame(height: promptFocused ? 280 : 380)
					.cornerRadius(12)
					.shadow(radius: 4)
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

			if let errorMessage = videoFetcher.errorMessage {
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

			TextField("Enter prompt…", text: $videoFetcher.prompt, axis: .vertical)
				.lineLimit(1...3)
				.textFieldStyle(.roundedBorder)
				.disabled(videoFetcher.isProcessing)
				.focused($promptFocused)

			HStack(spacing: 12) {
				if requiresAttachment {
					PhotosPicker(selection: $selectedItem, matching: pickerFilter) {
						Label("Attach", systemImage: "paperclip")
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
		}.onChange(of: selectedItem) {
			handleSelectionChange(selectedItem)
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
				selectedMediaPreview = previewImage
			}
		}
	}

	private func generate() {
		guard !trimmedPrompt.isEmpty else { return }

		if requiresAttachment, selectedItem == nil {
			return
		}

		dismissKeyboard()
		videoFetcher.fetchVideo(
			model: model,
			inputType: inputType,
			selectedItem: selectedItem
		)
	}

	private func clearAttachment() {
		selectedItem = nil
		selectedMediaPreview = nil
		videoFetcher.reset()
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
