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

	var prompt: String = ""
	var generatedImage: UIImage?
	var isProcessing: Bool = false
	var errorMessage: String?

	func reset() {
		prompt = ""
		generatedImage = nil
		errorMessage = nil
		isProcessing = false
	}

	func fetchImage(model: ImageModel, inputType: ModelInputType, selectedItem: PhotosPickerItem)
		async
	{
		let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmedPrompt.isEmpty else { return }

		isProcessing = true
		errorMessage = nil
		generatedImage = nil

		defer {
			isProcessing = false
		}

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
				guard let referenceData = try await selectedItem.loadTransferable(type: Data.self)
				else {
					throw DecartError.invalidInput("Failed to load the selected image")
				}

				let fileInput = FileInput.image(
					data: referenceData,
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
			guard let image = UIImage(data: data) else {
				errorMessage = "Failed to decode image data"
				return
			}
			generatedImage = image
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
