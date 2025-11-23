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
	@FocusState private var promptFocused: Bool

	private var inputType: ModelInputType {
		ModelsInputFactory.imageInputType(for: model)
	}

	private var requiresReference: Bool {
		inputType == .imageToImage
	}

	private var canSend: Bool {
		let hasPrompt = !imageFetcher.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		let hasReference = !requiresReference || selectedItem != nil
		return hasPrompt && hasReference && !imageFetcher.isProcessing
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
					description: Text(
						requiresReference
							? "Enter a prompt and pick a reference image."
							: "Enter a prompt to start."
					)
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
				HStack {
					Image(uiImage: preview)
						.resizable()
						.scaledToFill()
						.frame(width: 64, height: 64)
						.clipShape(RoundedRectangle(cornerRadius: 8))
					Text("Reference attached")
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

			TextField("Enter prompt…", text: $imageFetcher.prompt, axis: .vertical)
				.lineLimit(1...3)
				.textFieldStyle(.roundedBorder)
				.disabled(imageFetcher.isProcessing)
				.focused($promptFocused)

			HStack(spacing: 12) {
				if requiresReference {
					PhotosPicker(selection: $selectedItem, matching: .images) {
						Label("Reference", systemImage: "photo")
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
			guard let selectedItem else {
				selectedImagePreview = nil
				return
			}
			Task {
				let imagePreview = try? await selectedItem.loadTransferable(
					type: Data.self
				)
				if let uiImage = UIImage(data: imagePreview ?? Data()) {
					selectedImagePreview = uiImage
				}
			}
		}
	}

	private func generate() {
		dismissKeyboard()
		Task {
			guard let selectedItem else {
				return
			}
			await imageFetcher.fetchImage(
				model: model,
				inputType: inputType,
				selectedItem: selectedItem
			)
		}
	}

	private func clearAttachment() {
		selectedItem = nil
		selectedImagePreview = nil
		imageFetcher.reset()
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
		GenerateImageView(model: .lucy_pro_t2i)
	}
}
