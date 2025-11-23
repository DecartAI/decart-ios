//
//  RealtimeConfiguration.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 04/11/2025.
//

import Foundation
@preconcurrency import WebRTC

public struct RealtimeConfiguration: Sendable {
	public let model: ModelDefinition
	public let initialState: ModelState
	public let connection: ConnectionConfig
	public let media: MediaConfig

	public init(
		model: ModelDefinition,
		initialState: ModelState,
		connection: ConnectionConfig = .init(),
		media: MediaConfig = .init()
	) {
		self.model = model
		self.initialState = initialState
		self.connection = connection
		self.media = media
	}

	// MARK: - Sub-Configurations

	public struct ConnectionConfig: Sendable {
		public let iceServers: [String]
		public let connectionTimeout: Int32
		public let pingInterval: Int32

		public init(
			iceServers: [String] = ["stun:stun.l.google.com:19302"],
			connectionTimeout: Int32 = 1000,
			pingInterval: Int32 = 2000
		) {
			self.iceServers = iceServers
			self.connectionTimeout = connectionTimeout
			self.pingInterval = pingInterval
		}

		public func makeRTCConfiguration() -> RTCConfiguration {
			let config = RTCConfiguration()
			config.iceServers = [RTCIceServer(urlStrings: iceServers)]
			config.sdpSemantics = .unifiedPlan
			config.continualGatheringPolicy = .gatherContinually
			config.iceConnectionReceivingTimeout = connectionTimeout
			config.iceBackupCandidatePairPingInterval = pingInterval
			return config
		}
	}

	public struct MediaConfig: Sendable {
		public let video: VideoConfig

		public init(video: VideoConfig = .init()) {
			self.video = video
		}

		public var offerConstraints: RTCMediaConstraints {
			RTCMediaConstraints(
				mandatoryConstraints: nil,
				optionalConstraints: ["OfferToReceiveVideo": "true"]
			)
		}

		public var connectionConstraints: RTCMediaConstraints {
			RTCMediaConstraints(
				mandatoryConstraints: nil,
				optionalConstraints: nil
			)
		}
	}

	public struct VideoConfig: Sendable {
		public let maxBitrate: Int
		public let minBitrate: Int
		public let maxFramerate: Int
		public let preferredCodec: String

		public init(
			maxBitrate: Int = 3_800_000,
			minBitrate: Int = 800_000,
			maxFramerate: Int = 30,
			preferredCodec: String = "VP8"
		) {
			self.maxBitrate = maxBitrate
			self.minBitrate = minBitrate
			self.maxFramerate = maxFramerate
			self.preferredCodec = preferredCodec
		}

		@MainActor
		public func configure(transceiver: RTCRtpTransceiver, factory: RTCPeerConnectionFactory) {
			let supportedCodecs = factory.rtpSenderCapabilities(forKind: "video").codecs

			var preferredCodecs: [RTCRtpCodecCapability] = []
			var otherCodecs: [RTCRtpCodecCapability] = []
			var utilityCodecs: [RTCRtpCodecCapability] = []

			let preferredCodecName = preferredCodec.uppercased()

			for codec in supportedCodecs {
				let codecNameUpper = codec.name.uppercased()
				if codecNameUpper == preferredCodecName {
					preferredCodecs.append(codec)
				} else if codecNameUpper == "RTX" || codecNameUpper == "RED"
					|| codecNameUpper == "ULPFEC"
				{
					utilityCodecs.append(codec)
				} else {
					otherCodecs.append(codec)
				}
			}

			let sortedCodecs = preferredCodecs + otherCodecs + utilityCodecs
			try? transceiver.setCodecPreferences(sortedCodecs, error: ())

			let sender = transceiver.sender
			let parameters = sender.parameters
			if parameters.encodings.indices.contains(0) {
				let encodingParam = parameters.encodings[0]
				encodingParam.maxBitrateBps = NSNumber(value: maxBitrate)
				encodingParam.minBitrateBps = NSNumber(value: minBitrate)
				encodingParam.maxFramerate = NSNumber(value: maxFramerate)

				parameters.encodings[0] = encodingParam
				sender.parameters = parameters
			}
		}
	}
}
