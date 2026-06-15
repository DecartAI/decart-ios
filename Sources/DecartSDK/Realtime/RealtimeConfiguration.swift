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
	public let observability: ObservabilityConfig
	/// Opt-in DEBUG-quality measurement: asks the server to re-stamp the pixel
	/// marker (`pixel_latency=1`) so the SDK can read true glass-to-glass latency
	/// off the rendered frames. Diagnostic only: the marker is **visible** and adds
	/// per-frame pixel work — don't enable it for production. Requires a stream
	/// built via `DecartClient.createLocalCameraStream(debugQuality: true)`.
	public let debugQuality: Bool

	public init(
		model: ModelDefinition,
		initialPrompt: DecartPrompt = .init(text: ""),
		resolution: Resolution? = nil,
		connection: ConnectionConfig = .init(),
		media: MediaConfig = .init(),
		observability: ObservabilityConfig = .init(),
		debugQuality: Bool = false
	) {
		self.model = model
		self.initialPrompt = initialPrompt
		self.resolution = resolution
		self.connection = connection
		self.media = media
		self.observability = observability
		self.debugQuality = debugQuality
	}

	// MARK: - Sub-Configurations

	public struct ConnectionConfig: Sendable {
		public let connectionTimeout: TimeInterval
		public let reconnectAttempts: Int
		public let bundleInitialStateInJoin: Bool

		public init(
			connectionTimeout: TimeInterval = 15,
			reconnectAttempts: Int = 10,
			bundleInitialStateInJoin: Bool = true
		) {
			self.connectionTimeout = connectionTimeout
			self.reconnectAttempts = reconnectAttempts
			self.bundleInitialStateInJoin = bundleInitialStateInJoin
		}

		var connectOptions: ConnectOptions {
			ConnectOptions(
				autoSubscribe: true,
				reconnectAttempts: reconnectAttempts,
				socketConnectTimeoutInterval: connectionTimeout,
				primaryTransportConnectTimeout: connectionTimeout,
				publisherTransportConnectTimeout: connectionTimeout
			)
		}
	}

	/// In-session observability (connection-quality signal). Defaults on; the
	/// `connectionQualityEnabled` flag gates LiveKit's 1 Hz stats polling so
	/// opted-out callers pay no overhead.
	public struct ObservabilityConfig: Sendable {
		public let connectionQualityEnabled: Bool
		public let connectionQuality: ConnectionQualityThresholds

		public init(
			connectionQualityEnabled: Bool = true,
			connectionQuality: ConnectionQualityThresholds = .default
		) {
			self.connectionQualityEnabled = connectionQualityEnabled
			self.connectionQuality = connectionQuality
		}

		/// Thresholds to hand the media channel, or nil when disabled.
		var thresholdsIfEnabled: ConnectionQualityThresholds? {
			connectionQualityEnabled ? connectionQuality : nil
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
