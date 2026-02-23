//
//  CameraHelpers.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 04/11/2025.
//
import AVFoundation
import WebRTC

public extension AVCaptureDevice {
	static func availableCameras() -> [AVCaptureDevice] {
		RTCCameraVideoCapturer.captureDevices().sorted {
			let nameCompare = $0.localizedName.localizedStandardCompare($1.localizedName)
			if nameCompare != .orderedSame {
				return nameCompare == .orderedAscending
			}
			return $0.uniqueID < $1.uniqueID
		}
	}

	/// Pick a format that meets (or exceeds) the requested dimensions in either orientation.
	func pickFormat(minWidth: Int, minHeight: Int) throws -> AVCaptureDevice.Format {
		let formats = RTCCameraVideoCapturer.supportedFormats(for: self)

		if let match = formats.first(where: {
			let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
			let landscape = d.width >= minWidth && d.height >= minHeight
			let portrait = d.height >= minWidth && d.width >= minHeight
			return landscape || portrait
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

	static func pickCamera(
		position: AVCaptureDevice.Position,
		fallbackToAny: Bool = false
	) throws -> AVCaptureDevice {
		let devices = availableCameras()
		guard !devices.isEmpty else {
			throw CameraError.noCameraDeviceAvailable
		}

		if let matchingDevice = devices.first(where: { $0.position == position }) {
			return matchingDevice
		}

		if fallbackToAny, let firstDevice = devices.first {
			return firstDevice
		}

		switch position {
		case .front:
			throw CameraError.noFrontCameraDetected
		case .back:
			throw CameraError.noBackCameraDetected
		default:
			throw CameraError.noCameraDeviceAvailable
		}
	}

	static func nextCamera(after currentDeviceID: String?) -> AVCaptureDevice? {
		let devices = availableCameras()
		guard !devices.isEmpty else { return nil }

		guard
			let currentDeviceID,
			let currentIndex = devices.firstIndex(where: { $0.uniqueID == currentDeviceID })
		else {
			return devices.first
		}

		let nextIndex = (currentIndex + 1) % devices.count
		return devices[nextIndex]
	}
}
