//
//  GenerateImageView.swift
//  Example
//
//  Created by Alon Bar-el on 19/11/2025.
//

import DecartSDK
import Factory
import PhotosUI
import SwiftUI

struct GenerateImageView: View {
	let model: ImageModel

	@Injected(\.decartClient) private var decartClient

	@State private var prompt: String = ""
	@State private var selectedItem: PhotosPickerItem?
	@State private var selectedImagePreview: UIImage?
	@State private var selectedImageData: Data?
	@State private var generatedImage: UIImage?
	@State private var isProcessing = false
	@State private var errorMessage: String?

	private var inputType: ModelInputType {
		ModelsInputFactory.imageInputType(for: model)
	}

	private var requiresReference: Bool {
		inputType == .imageToImage
	}

	private var canSend: Bool {
		let hasPrompt = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		let hasReference = !requiresReference || selectedImageData != nil
		return hasPrompt && hasReference && !isProcessing
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
			if let image = generatedImage {
				Image(uiImage: image)
					.resizable()
					.scaledToFit()
					.cornerRadius(12)
					.shadow(radius: 4)
				Button("Save to Photos") {
					UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
				}
				.font(.footnote.weight(.semibold))
			} else if isProcessing {
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

			if let errorMessage {
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

			TextField("Enter prompt…", text: $prompt, axis: .vertical)
				.lineLimit(1...3)
				.textFieldStyle(.roundedBorder)
				.disabled(isProcessing)

			HStack(spacing: 12) {
				if requiresReference {
					PhotosPicker(selection: $selectedItem, matching: .images) {
						Label("Reference", systemImage: "photo")
					}
					.onChange(of: selectedItem) { newItem in
						loadSelectedImage(from: newItem)
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

	private func loadSelectedImage(from item: PhotosPickerItem?) {
		guard let item else {
			clearAttachment()
			return
		}

		Task {
			do {
				if let data = try await item.loadTransferable(type: Data.self),
					let image = UIImage(data: data)
				{
					await MainActor.run {
						selectedImageData = data
						selectedImagePreview = image
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
		let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmedPrompt.isEmpty else { return }

		isProcessing = true
		errorMessage = nil
		generatedImage = nil

		Task {
			do {
				let processClient: ProcessClient

				switch inputType {
				case .textToImage:
					let input = TextToImageInput(prompt: trimmedPrompt)
					processClient = try decartClient.createProcessClient(
						model: model,
						input: input
					)

				case .imageToImage:
					guard let data = selectedImageData else {
						throw DecartError.invalidInput("Please select an image first")
					}

					let fileInput = makeFileInput(
						from: data,
						filename: "reference.jpg"
					)
					let input = ImageToImageInput(prompt: trimmedPrompt, data: fileInput)
					processClient = try decartClient.createProcessClient(
						model: model,
						input: input
					)

				default:
					throw DecartError.invalidInput("Unsupported input type")
				}

				let data = try await processClient.process()
				if let image = UIImage(data: data) {
					await MainActor.run {
						generatedImage = image
					}
				} else {
					await MainActor.run {
						errorMessage = "Failed to decode image data"
					}
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

	private func makeFileInput(from data: Data, filename: String) -> FileInput {
		let sanitizedName = (filename as NSString).lastPathComponent
		let hasExtension = !(sanitizedName as NSString).pathExtension.isEmpty
		let finalName = hasExtension ? sanitizedName : "\(sanitizedName).dat"
		return FileInput(data: data, filename: finalName)
	}

	private func clearAttachment() {
		selectedItem = nil
		selectedImageData = nil
		selectedImagePreview = nil
	}
}

#Preview {
	NavigationView {
		GenerateImageView(model: .lucy_pro_t2i)
	}
}
