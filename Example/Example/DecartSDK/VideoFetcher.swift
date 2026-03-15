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

	func fetchVideo(model: VideoModel, selectedItem: PhotosPickerItem?) {
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
				selectedItem: selectedItem
			)
		}
	}

	private func generateVideo(
		trimmedPrompt: String,
		model: VideoModel,
		selectedItem: PhotosPickerItem?
	) async {
		defer {
			isProcessing = false
		}

		do {
			let result = try await submitVideoJob(
				prompt: trimmedPrompt,
				model: model,
				selectedItem: selectedItem
			)
			guard !Task.isCancelled else { return }

			switch result {
			case .completed(_, let data):
				let tempURL = FileManager.default.temporaryDirectory
					.appendingPathComponent(UUID().uuidString)
					.appendingPathExtension("mp4")
				try data.write(to: tempURL, options: .atomic)

				videoPlayer?.pause()
				generatedVideoURL = tempURL
				videoPlayer = AVPlayer(url: tempURL)
			case .failed(_, let error):
				errorMessage = error
			}
		} catch {
			if Task.isCancelled {
				return
			}
			errorMessage = error.localizedDescription
		}
	}

	private func submitVideoJob(
		prompt: String,
		model: VideoModel,
		selectedItem: PhotosPickerItem?
	) async throws -> QueueJobResult {
		let fileInput = try await loadFileInput(from: selectedItem)
		let input = try VideoToVideoInput(prompt: prompt, data: fileInput)
		return try await decartClient.queue.submitAndPoll(model: model, input: input)
	}

	private func loadFileInput(from item: PhotosPickerItem?) async throws -> FileInput {
		guard let item else {
			throw DecartError.invalidInput("No media selected")
		}

		guard let data = try await item.loadTransferable(type: Data.self) else {
			throw DecartError.invalidInput("Failed to load selected media")
		}

		let mediaType = item.supportedContentTypes.first(where: {
			$0.conforms(to: .movie) || $0.conforms(to: .video)
		})

		return try FileInput.from(data: data, uniformType: mediaType)
	}
}
