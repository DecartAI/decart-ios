//
//  GenerateImageView.swift
//  Example
//
//  Created by Alon Bar-el on 19/11/2025.
//

import DecartSDK
import Observation
import PhotosUI
import SwiftUI

struct GenerateImageView: View {
	let model: ImageModel

	@State private var imageFetcher = ImageFetcher()
	@State private var selectedItem: PhotosPickerItem?
	@State private var selectedImagePreview: UIImage?
	@State private var referenceItem: PhotosPickerItem?
	@State private var referenceImagePreview: UIImage?
	@State private var previewLoadTask: Task<Void, Never>?
	@State private var referencePreviewLoadTask: Task<Void, Never>?
	@FocusState private var promptFocused: Bool

	private var canSend: Bool {
		let hasPrompt = !imageFetcher.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		let hasInput = selectedItem != nil
		return hasPrompt && hasInput && !imageFetcher.isProcessing
	}

	var body: some View {
		VStack(spacing: 16) {
			ScrollView {
				resultSection
					.padding(.horizontal)
					.padding(.top)
			}
			.contentShape(Rectangle())
			.onTapGesture {
				dismissKeyboard()
			}

			Divider()

			inputSection
				.padding(.horizontal)
				.padding(.bottom)
		}
		.onDisappear {
			previewLoadTask?.cancel()
			previewLoadTask = nil
			referencePreviewLoadTask?.cancel()
			referencePreviewLoadTask = nil
			imageFetcher.cancelGeneration()
			imageFetcher.reset()
			selectedItem = nil
			selectedImagePreview = nil
			referenceItem = nil
			referenceImagePreview = nil
		}
		.navigationTitle(model.rawValue)
		.navigationBarTitleDisplayMode(.inline)
	}

	private var resultSection: some View {
		VStack(spacing: 12) {
			if let image = imageFetcher.generatedImage {
				Image(uiImage: image)
					.resizable()
					.scaledToFit()
					.cornerRadius(12)
					.shadow(radius: 4)
				Button("Save to Photos") {
					UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
				}
				.font(.footnote.weight(.semibold))
			} else if imageFetcher.isProcessing {
				ProgressView("Generating...")
					.progressViewStyle(.circular)
					.padding()
			} else {
				ContentUnavailableView(
					"Ready to generate",
					systemImage: "photo.badge.plus",
					description: Text("Enter a prompt and pick an input image.")
				)
				.padding(.vertical, 24)
			}

			if let errorMessage = imageFetcher.errorMessage {
				Text(errorMessage)
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
	}

	private var inputSection: some View {
		VStack(spacing: 12) {
			if let preview = selectedImagePreview {
				attachmentRow(label: "Input image", preview: preview) {
					clearInputAttachment()
				}
			}

			if let preview = referenceImagePreview {
				attachmentRow(label: "Reference image", preview: preview) {
					clearReferenceAttachment()
				}
			}

			TextField("Enter prompt…", text: $imageFetcher.prompt, axis: .vertical)
				.lineLimit(1 ... 3)
				.textFieldStyle(.roundedBorder)
				.disabled(imageFetcher.isProcessing)
				.focused($promptFocused)

			HStack(spacing: 12) {
				PhotosPicker(selection: $selectedItem, matching: .images) {
					Label("Input", systemImage: "photo")
				}

				PhotosPicker(selection: $referenceItem, matching: .images) {
					Label("Reference", systemImage: "photo.on.rectangle")
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
		.onChange(of: selectedItem) {
			previewLoadTask?.cancel()
			guard let selectedItem else {
				selectedImagePreview = nil
				return
			}
			previewLoadTask = Task {
				guard !Task.isCancelled else { return }
				let imagePreview = try? await selectedItem.loadTransferable(type: Data.self)
				guard !Task.isCancelled else { return }
				if let uiImage = UIImage(data: imagePreview ?? Data()) {
					selectedImagePreview = uiImage
				}
			}
		}
		.onChange(of: referenceItem) {
			referencePreviewLoadTask?.cancel()
			guard let referenceItem else {
				referenceImagePreview = nil
				return
			}
			referencePreviewLoadTask = Task {
				guard !Task.isCancelled else { return }
				let imagePreview = try? await referenceItem.loadTransferable(type: Data.self)
				guard !Task.isCancelled else { return }
				if let uiImage = UIImage(data: imagePreview ?? Data()) {
					referenceImagePreview = uiImage
				}
			}
		}
	}

	private func attachmentRow(label: String, preview: UIImage, onClear: @escaping () -> Void) -> some View {
		HStack {
			Image(uiImage: preview)
				.resizable()
				.scaledToFill()
				.frame(width: 64, height: 64)
				.clipShape(RoundedRectangle(cornerRadius: 8))
			Text(label)
				.font(.subheadline)
			Spacer()
			Button(action: onClear) {
				Image(systemName: "xmark.circle.fill")
					.foregroundStyle(.secondary)
			}
		}
	}

	private func generate() {
		dismissKeyboard()
		guard let selectedItem else { return }
		imageFetcher.fetchImage(
			model: model,
			selectedItem: selectedItem,
			referenceSelectedItem: referenceItem
		)
	}

	private func clearInputAttachment() {
		selectedItem = nil
		selectedImagePreview = nil
		imageFetcher.reset()
		dismissKeyboard()
	}

	private func clearReferenceAttachment() {
		referenceItem = nil
		referenceImagePreview = nil
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
		GenerateImageView(model: .lucy_pro_i2i)
	}
}
