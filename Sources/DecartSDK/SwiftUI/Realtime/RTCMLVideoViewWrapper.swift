@preconcurrency import LiveKit
import SwiftUI

#if os(iOS)
/// A SwiftUI view that renders a LiveKit video track.
public struct RTCMLVideoViewWrapper: UIViewRepresentable {
	public weak var track: VideoTrack?
	public var mirror: Bool

	public init(track: VideoTrack?, mirror: Bool = false) {
		self.track = track
		self.mirror = mirror
	}

	public func makeUIView(context: Context) -> VideoView {
		let view = VideoView()
		view.layoutMode = .fill
		view.mirrorMode = mirror ? .mirror : .off
		view.track = track
		return view
	}

	public func updateUIView(_ uiView: VideoView, context: Context) {
		uiView.track = track
		uiView.mirrorMode = mirror ? .mirror : .off
	}

	public static func dismantleUIView(_ uiView: VideoView, coordinator: ()) {
		uiView.track = nil
	}
}
#elseif os(macOS)
/// A SwiftUI view that renders a LiveKit video track.
public struct RTCMLVideoViewWrapper: NSViewRepresentable {
	public weak var track: VideoTrack?
	public var mirror: Bool

	public init(track: VideoTrack?, mirror: Bool = false) {
		self.track = track
		self.mirror = mirror
	}

	public func makeNSView(context: Context) -> VideoView {
		let view = VideoView()
		view.layoutMode = .fill
		view.mirrorMode = mirror ? .mirror : .off
		view.track = track
		return view
	}

	public func updateNSView(_ nsView: VideoView, context: Context) {
		nsView.track = track
		nsView.mirrorMode = mirror ? .mirror : .off
	}

	public static func dismantleNSView(_ nsView: VideoView, coordinator: ()) {
		nsView.track = nil
	}
}
#endif
