//
//  CaptureDataTypes.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 04/11/2025.
//

enum CameraError: Error {
	case simulatorUnsupported
	case noFrontCameraDetected
	case noBackCameraDetected
	case noSupportedFormatFound
	case noSuitableFPSRange
	case captureFailed(Error)

	var errorDescription: String? {
		switch self {
		case .simulatorUnsupported: return "Camera is not available on the simulator."
		case .noFrontCameraDetected: return "No front camera detected."
		case .noSupportedFormatFound: return "No supported camera format found for the requested resolution."
		case .noSuitableFPSRange: return "No suitable FPS range available for the requested FPS."
		case .noBackCameraDetected: return "No back camera detected."
		case .captureFailed(let err): return "Camera capture failed: \(err.localizedDescription)"
		}
	}
}
