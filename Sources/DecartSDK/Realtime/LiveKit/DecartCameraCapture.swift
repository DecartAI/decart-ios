@preconcurrency import LiveKit
import UIKit

/// Camera-capture helpers for the realtime LiveKit publisher.
///
/// The realtime inference server eagerly publishes its output track at
/// the dimensions the input track advertised in its publication
/// metadata (the LiveKit `TrackInfo` populated from the publisher's
/// `AddTrackRequest`), to overlap the output SDP renegotiation with
/// the per-session time-to-first-output-frame on the inference side.
/// Passing the model's natural landscape `(W, H)` straight to
/// `CameraCaptureOptions` on a portrait device forces the capture to
/// landscape, the published metadata to landscape, and relies on the
/// WebRTC CVO rotation extension to deliver portrait frames. The
/// mismatch triggers a server-side republish, which trips a libwebrtc
/// transceiver-reuse race that intermittently leaves the client
/// without a `didSubscribeTrack(_:)` event for the new track (black
/// screen).
public enum DecartCameraCapture {
	/// `Dimensions` oriented for the device's current interface
	/// orientation. Pass the model's natural landscape `(width, height)`;
	/// portrait devices get the transposed dims.
	@MainActor
	public static func orientedDimensions(modelWidth: Int, modelHeight: Int) -> Dimensions {
		let short = min(modelWidth, modelHeight)
		let long = max(modelWidth, modelHeight)
		let (w, h) = isInterfaceOrientationPortrait() ? (short, long) : (long, short)
		return Dimensions(width: Int32(w), height: Int32(h))
	}

	@MainActor
	private static func isInterfaceOrientationPortrait() -> Bool {
		let scenes = UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
		let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
		if let orientation = scene?.interfaceOrientation {
			if orientation.isPortrait { return true }
			if orientation.isLandscape { return false }
		}
		let b = UIScreen.main.bounds
		return b.height >= b.width
	}
}
