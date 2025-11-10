//
//  RTCMLVideoViewWrapper.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 04/11/2025.
//
import SwiftUI
import WebRTC

#if os(iOS)
/// A SwiftUI View that renders a WebRTC video track.
public struct RTCMLVideoViewWrapper: UIViewRepresentable {
	public weak var track: RTCVideoTrack?
	public var mirror: Bool

	/// Creates a new video view for the given track.
	public init(track: RTCVideoTrack?, mirror: Bool = false) {
		self.track = track
		self.mirror = mirror
	}

	public final class Coordinator {
		weak var view: RTCMTLVideoView?
		weak var lastTrack: RTCVideoTrack?
		var lastMirror: Bool = false

		// Add a public init for the coordinator
		public init() {}
	}

	public func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	public func makeUIView(context: Context) -> RTCMTLVideoView {
		let view = RTCMTLVideoView()
		view.videoContentMode = .scaleAspectFill
		view.transform = mirror ? CGAffineTransform(scaleX: -1, y: 1) : .identity
		context.coordinator.view = view
		context.coordinator.lastMirror = mirror

		if let track {
			track.add(view)
			context.coordinator.lastTrack = track
		}
		return view
	}

	public func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
		// If the track changed, rewire attachment
		if context.coordinator.lastTrack !== track {
			context.coordinator.lastTrack?.remove(uiView)
			if let track {
				track.add(uiView)
			}
			context.coordinator.lastTrack = track
		}

		if context.coordinator.lastMirror != mirror {
			uiView.transform = mirror ? CGAffineTransform(scaleX: -1, y: 1) : .identity
			context.coordinator.lastMirror = mirror
		}
	}

	public static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
		coordinator.lastTrack?.remove(uiView)
		coordinator.view = nil
		coordinator.lastTrack = nil
	}
}
#endif
