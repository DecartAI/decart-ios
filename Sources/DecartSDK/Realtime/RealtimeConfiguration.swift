//
//  RealtimeConfiguration.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 04/11/2025.
//

import Foundation
@preconcurrency import LiveKit

/// Output resolution requested from the realtime server.
public enum Resolution: String, Sendable {
	case p720 = "720p"
	case p1080 = "1080p"
}

public struct RealtimeConfiguration: Sendable {
	public let model: ModelDefinition
	public let initialPrompt: DecartPrompt
	public let resolution: Resolution?
	public let connection: ConnectionConfig
	public let media: MediaConfig

	public init(
		model: ModelDefinition,
		initialPrompt: DecartPrompt = .init(text: ""),
		resolution: Resolution? = nil,
		connection: ConnectionConfig = .init(),
		media: MediaConfig = .init()
	) {
		self.model = model
		self.initialPrompt = initialPrompt
		self.resolution = resolution
		self.connection = connection
		self.media = media
	}

	// MARK: - Sub-Configurations

	public struct ConnectionConfig: Sendable {
		public let connectionTimeout: TimeInterval
		public let signalingConnectTimeout: TimeInterval
		public let roomInfoTimeout: TimeInterval
		public let requestTimeout: TimeInterval
		public let sessionRetryAttempts: Int
		public let reconnectAttempts: Int

		public init(
			connectionTimeout: TimeInterval = 15,
			signalingConnectTimeout: TimeInterval = 60,
			roomInfoTimeout: TimeInterval = 15,
			requestTimeout: TimeInterval = 30,
			sessionRetryAttempts: Int = 5,
			reconnectAttempts: Int = 10
		) {
			self.connectionTimeout = connectionTimeout
			self.signalingConnectTimeout = signalingConnectTimeout
			self.roomInfoTimeout = roomInfoTimeout
			self.requestTimeout = requestTimeout
			self.sessionRetryAttempts = sessionRetryAttempts
			self.reconnectAttempts = reconnectAttempts
		}

		var connectOptions: ConnectOptions {
			ConnectOptions(
				autoSubscribe: true,
				reconnectAttempts: reconnectAttempts,
				socketConnectTimeoutInterval: connectionTimeout,
				primaryTransportConnectTimeout: connectionTimeout,
				publisherTransportConnectTimeout: connectionTimeout,
				enableMicrophone: false
			)
		}
	}

	public struct MediaConfig: Sendable {
		public let video: VideoConfig

		public init(video: VideoConfig = .init()) {
			self.video = video
		}
	}

	public struct VideoConfig: Sendable {
		public let maxBitrate: Int
		public let maxFramerate: Int
		public let preferredCodec: String
		public let simulcast: Bool

		public init(
			maxBitrate: Int = 3_500_000,
			maxFramerate: Int = 30,
			preferredCodec: String = "h264",
			simulcast: Bool = true
		) {
			self.maxBitrate = maxBitrate
			self.maxFramerate = maxFramerate
			self.preferredCodec = preferredCodec
			self.simulcast = simulcast
		}

		var publishOptions: VideoPublishOptions {
			VideoPublishOptions(
				encoding: VideoEncoding(maxBitrate: maxBitrate, maxFps: maxFramerate),
				simulcast: simulcast,
				preferredCodec: LiveKit.VideoCodec.from(name: preferredCodec)
			)
		}
	}
}
