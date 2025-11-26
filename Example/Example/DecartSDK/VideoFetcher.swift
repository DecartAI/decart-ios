//
//  VideoFetcher.swift
//  Example
//
//  Created by Alon Bar-el on 23/11/2025.
//
import AVKit
import DecartSDK
import Factory
import Foundation
import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class VideoFetcher {
	@ObservationIgnored
	private let decartClient = Container.shared.decartClient()

	@ObservationIgnored
	private static let urlSession: URLSession = {
		let config = URLSessionConfiguration.default
		config.urlCache = nil
		config.requestCachePolicy = .reloadIgnoringLocalCacheData
		return URLSession(configuration: config)
	}()

	private var generateVideoTask: Task<Void, Never>?

	var prompt: String = ""
	var generatedVideoURL: URL?
	var videoPlayer: AVPlayer?
	var isProcessing: Bool = false
	var errorMessage: String?

	func reset() {
		prompt = ""

		if let videoURL = generatedVideoURL {
			try? FileManager.default.removeItem(at: videoURL)
		}

		generatedVideoURL = nil
		errorMessage = nil
		isProcessing = false
		videoPlayer?.pause()
		videoPlayer = nil
		generateVideoTask?.cancel()
		generateVideoTask = nil
	}

	func cancelGeneration() {
		generateVideoTask?.cancel()
		generateVideoTask = nil
		videoPlayer?.pause()
	}

	func fetchVideo(model: VideoModel, inputType: ModelInputType, selectedItem: PhotosPickerItem?) {
		let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmedPrompt.isEmpty else { return }

		generateVideoTask?.cancel()
		isProcessing = true
		errorMessage = nil
		generatedVideoURL = nil

		generateVideoTask = Task { [weak self, selectedItem] in
			if let videoURL = self?.generatedVideoURL {
				try? FileManager.default.removeItem(at: videoURL)
			}

			await self?.generateVideo(
				trimmedPrompt: trimmedPrompt,
				model: model,
				inputType: inputType,
				selectedItem: selectedItem
			)
		}
	}

	private func generateVideo(
		trimmedPrompt: String,
		model: VideoModel,
		inputType: ModelInputType,
		selectedItem: PhotosPickerItem?
	) async {
		defer {
			isProcessing = false
		}

		do {
			let processClient = try await buildProcessClient(
				prompt: trimmedPrompt,
				model: model,
				inputType: inputType,
				selectedItem: selectedItem
			)
			guard !Task.isCancelled else { return }

			let data = try await processClient.process()
			let tempURL = FileManager.default.temporaryDirectory
				.appendingPathComponent(UUID().uuidString)
				.appendingPathExtension("mp4")
			try data.write(to: tempURL, options: .atomic)

			if Task.isCancelled {
				return
			}

			videoPlayer?.pause()
			generatedVideoURL = tempURL
			videoPlayer = AVPlayer(url: tempURL)
		} catch {
			if Task.isCancelled {
				return
			}
			errorMessage = error.localizedDescription
		}
	}

	private func buildProcessClient(
		prompt: String,
		model: VideoModel,
		inputType: ModelInputType,
		selectedItem: PhotosPickerItem?
	) async throws -> ProcessClient {
		switch inputType {
		case .textToVideo:
			let input = try TextToVideoInput(prompt: prompt)
			return try decartClient.createProcessClient(model: model, input: input, session: Self.urlSession)

		case .imageToVideo:
			let fileInput = try await loadFileInput(from: selectedItem)
			let input = try ImageToVideoInput(prompt: prompt, data: fileInput)
			return try decartClient.createProcessClient(model: model, input: input, session: Self.urlSession)

		case .videoToVideo:
			let fileInput = try await loadFileInput(from: selectedItem)
			let input = try VideoToVideoInput(prompt: prompt, data: fileInput)
			return try decartClient.createProcessClient(model: model, input: input, session: Self.urlSession)

		default:
			throw DecartError.invalidInput("Unsupported input type")
		}
	}

	private func loadFileInput(from item: PhotosPickerItem?) async throws -> FileInput {
		guard let item else {
			throw DecartError.invalidInput("No media selected")
		}

		guard var data = try await item.loadTransferable(type: Data.self) else {
			throw DecartError.invalidInput("Failed to load selected media")
		}

		let mediaType = item.supportedContentTypes.first(where: {
			$0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .image)
		})

		if let type = mediaType, type.conforms(to: .image) {
			guard let image = UIImage(data: data),
			      let fixedImage = image.fixOrientation(),
			      let jpegData = fixedImage.jpegData(compressionQuality: 0.9)
			else {
				throw DecartError.invalidInput("Failed to process image")
			}
			data = jpegData
		}

		return try FileInput.from(data: data, uniformType: mediaType)
	}
}
