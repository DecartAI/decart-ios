//
//  DraggableRTCVideoView.swift
//  Example
//
//  Created by Alon Bar-el on 10/11/2025.
//

import DecartSDK
import SwiftUI
import WebRTC

struct DraggableRTCVideoView: View {
	let track: RTCVideoTrack
	let mirror: Bool

	@State private var offset: CGSize = .zero
	@State private var lastOffset: CGSize = .zero
	// Update these for desired container size
	let pipSize = CGSize(width: 120, height: 180)
	let margin: CGFloat = 14
	var body: some View {
		GeometryReader { geo in
			RTCMLVideoViewWrapper(
				track: track,
				mirror: mirror
			)
			.frame(width: pipSize.width, height: pipSize.height)
			.cornerRadius(12)
			.shadow(radius: 8)
			.offset(x: offset.width, y: offset.height)
			.gesture(
				DragGesture()
					.onChanged { gesture in
						offset = CGSize(width: lastOffset.width + gesture.translation.width,
						                height: lastOffset.height + gesture.translation.height)
					}
					.onEnded { _ in
						// Calculate screen corners
						let width = geo.size.width
						let height = geo.size.height

						let cornerOffsets = [
							CGSize(width: margin, height: margin), // top-left
							CGSize(width: width - pipSize.width - margin, height: margin), // top-right
							CGSize(width: margin, height: height - pipSize.height - margin), // bottom-left
							CGSize(width: width - pipSize.width - margin, height: height - pipSize.height - margin) // bottom-right
						]
						// Find nearest corner by Euclidean distance
						let current = CGPoint(x: offset.width, y: offset.height)
						let nearest = cornerOffsets.min(by: { lhs, rhs in
							let dl = pow(Double(lhs.width - current.x), 2) + pow(Double(lhs.height - current.y), 2)
							let dr = pow(Double(rhs.width - current.x), 2) + pow(Double(rhs.height - current.y), 2)
							return dl < dr
						}) ?? .zero
						// Animate snap
						withAnimation(.spring()) {
							offset = nearest
						}
						lastOffset = offset
					}
			)
			.onAppear {
				// Start in bottom-right initially
				offset = CGSize(
					width: geo.size.width - pipSize.width - margin,
					height: geo.size.height - pipSize.height - margin
				)
				lastOffset = offset
			}
		}
	}
}
