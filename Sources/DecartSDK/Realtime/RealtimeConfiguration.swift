//
//  RealtimeConfiguration.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 04/11/2025.
//

public struct RealtimeConfig: Sendable {
	public let model: ModelDefinition
	public let initialState: ModelState?
	public let peerConnectionConfig: PeerConnectionConfig

	public init(
		model: ModelDefinition,
		initialState: ModelState? = nil,
		peerConnectionConfig: PeerConnectionConfig = .init()
	) {
		self.model = model
		self.initialState = initialState
		self.peerConnectionConfig = peerConnectionConfig
	}

	/// Settings that tune the underlying WebRTC sender.
	public struct PeerConnectionConfig: Sendable {
		public let maxBitrate: Int
		public let minBitrate: Int
		public let maxFramerate: Int

		public init(
			maxBitrate: Int = 3_800_000,
			minBitrate: Int = 800_000,
			maxFramerate: Int = 30
		) {
			self.maxBitrate = maxBitrate
			self.minBitrate = minBitrate
			self.maxFramerate = maxFramerate
		}
	}
}
