//
//  CameraHelpers.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 04/11/2025.
//
import AVFoundation
import WebRTC

public extension AVCaptureDevice {
	/// Pick a format that meets (or exceeds) the requested dimensions; falls back to the first available.
	func pickFormat(minWidth: Int, minHeight: Int) throws -> AVCaptureDevice.Format {
		let formats = RTCCameraVideoCapturer.supportedFormats(for: self)

		if let match = formats.first(where: {
			let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
			return d.width >= minWidth && d.height >= minHeight
		}) {
			return match
		}

		if let first = formats.first { return first }
		throw CameraError.noSupportedFormatFound
	}

	/// Pick an FPS supported by the given format.
	/// Prefers >= `preferred`; otherwise returns the highest supported FPS.
	func pickFPS(for format: AVCaptureDevice.Format, preferred: Int) throws -> Int {
		let ranges = format.videoSupportedFrameRateRanges

		if let r = ranges.first(where: { $0.maxFrameRate >= Double(preferred) }) {
			// Clamp to the range's max if `preferred` is above it
			return min(preferred, Int(r.maxFrameRate))
		}

		if let highest = ranges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
			return Int(highest.maxFrameRate)
		}

		throw CameraError.noSuitableFPSRange
	}

	static func pickCamera(position: AVCaptureDevice.Position) throws -> AVCaptureDevice {
		let devices = RTCCameraVideoCapturer.captureDevices()
		guard let front = devices.first(where: { $0.position == position }) else {
			throw CameraError.noFrontCameraDetected
		}
		return front
	}
}
