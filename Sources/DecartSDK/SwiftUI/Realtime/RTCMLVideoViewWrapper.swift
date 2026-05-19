@preconcurrency import LiveKit
import SwiftUI

#if os(iOS)
/// A SwiftUI view that renders a LiveKit video track.
public struct RTCMLVideoViewWrapper: UIViewRepresentable {
	public weak var track: VideoTrack?
	public var mirror: Bool
	public var layoutMode: VideoView.LayoutMode

	public init(track: VideoTrack?, mirror: Bool = false, layoutMode: VideoView.LayoutMode = .fit) {
		self.track = track
		self.mirror = mirror
		self.layoutMode = layoutMode
	}

	public func makeUIView(context: Context) -> VideoView {
		let view = VideoView()
		view.layoutMode = layoutMode
		view.mirrorMode = mirror ? .mirror : .off
		view.track = track
		return view
	}

	public func updateUIView(_ uiView: VideoView, context: Context) {
		uiView.track = track
		uiView.layoutMode = layoutMode
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
	public var layoutMode: VideoView.LayoutMode

	public init(track: VideoTrack?, mirror: Bool = false, layoutMode: VideoView.LayoutMode = .fit) {
		self.track = track
		self.mirror = mirror
		self.layoutMode = layoutMode
	}

	public func makeNSView(context: Context) -> VideoView {
		let view = VideoView()
		view.layoutMode = layoutMode
		view.mirrorMode = mirror ? .mirror : .off
		view.track = track
		return view
	}

	public func updateNSView(_ nsView: VideoView, context: Context) {
		nsView.track = track
		nsView.layoutMode = layoutMode
		nsView.mirrorMode = mirror ? .mirror : .off
	}

	public static func dismantleNSView(_ nsView: VideoView, coordinator: ()) {
		nsView.track = nil
	}
}
#endif
