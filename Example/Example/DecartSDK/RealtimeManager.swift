//
//  RealtimeCameraCapture.swift
//  Example
//
//  Created by Alon Bar-el on 04/11/2025.
//

import DecartSDK
import WebRTC

protocol RealtimeManager {
	var currentPrompt: Prompt { get set }
	var shouldMirror: Bool { get set }

	var connectionState: DecartRealtimeConnectionState { get }

	var localMediaStream: RealtimeMediaStream? { get }
	var remoteMediaStreams: RealtimeMediaStream? { get }

	func connect() async
	func switchCamera() async
	func cleanup() async
}
