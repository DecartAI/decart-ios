//
//  ImageFetcher.swift
//  Example
//
//  Created by Alon Bar-el on 23/11/2025.
//

import DecartSDK
import Factory
import Foundation
import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class ImageFetcher {
	@ObservationIgnored
	private let decartClient = Container.shared.decartClient()

	@ObservationIgnored
	private static let urlSession: URLSession = {
		let config = URLSessionConfiguration.default
		config.urlCache = nil
		config.requestCachePolicy = .reloadIgnoringLocalCacheData
		return URLSession(configuration: config)
	}()

	private var generateImageTask: Task<Void, Never>?

	var prompt: String = ""
	var generatedImage: UIImage?
	var isProcessing: Bool = false
	var errorMessage: String?

	func cancelGeneration() {
		generateImageTask?.cancel()
		generateImageTask = nil
	}

	func reset() {
		cancelGeneration()
		prompt = ""
		generatedImage = nil
		errorMessage = nil
		isProcessing = false
	}

	func fetchImage(model: ImageModel, selectedItem: PhotosPickerItem) {
		let currentPrompt = prompt
		guard !currentPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

		generateImageTask?.cancel()
		isProcessing = true
		errorMessage = nil
		generatedImage = nil

		generateImageTask = Task { [weak self] in
			await self?.performFetchImage(
				model: model,
				selectedItem: selectedItem,
				prompt: currentPrompt
			)
		}
	}

	private func performFetchImage(
		model: ImageModel,
		selectedItem: PhotosPickerItem,
		prompt: String
	) async {
		defer {
			isProcessing = false
		}

		do {
			guard !Task.isCancelled else { return }

			guard let rawData = try await selectedItem.loadTransferable(type: Data.self),
			      let image = UIImage(data: rawData),
			      let fixedImage = image.fixOrientation(),
			      let imageData = fixedImage.jpegData(compressionQuality: 0.9)
			else {
				throw DecartError.invalidInput("Failed to load image data")
			}

			guard !Task.isCancelled else { return }

			let fileInput = try FileInput.image(data: imageData)
			let input = try ImageToImageInput(prompt: prompt, data: fileInput)
			let processClient = try decartClient.createProcessClient(
				model: model,
				input: input,
				session: Self.urlSession
			)

			guard !Task.isCancelled else { return }

			let data = try await processClient.process()

			guard !Task.isCancelled else { return }

			guard let image = UIImage(data: data) else {
				errorMessage = "Failed to decode image data"
				return
			}
			generatedImage = image
		} catch {
			if !Task.isCancelled {
				errorMessage = error.localizedDescription
			}
		}
	}
}
