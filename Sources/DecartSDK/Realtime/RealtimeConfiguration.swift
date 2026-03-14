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
	public let initialPrompt: DecartPrompt
	public let connection: ConnectionConfig
	public let media: MediaConfig

	public init(
		model: ModelDefinition,
		initialPrompt: DecartPrompt = .init(text: ""),
		connection: ConnectionConfig = .init(),
		media: MediaConfig = .init()
	) {
		self.model = model
		self.initialPrompt = initialPrompt
		self.connection = connection
		self.media = media
	}

	// MARK: - Sub-Configurations

	public struct ConnectionConfig: Sendable {
		public let iceServers: [String]
		public let connectionTimeout: TimeInterval
		public let rtcConfiguration: RTCConfiguration

		public init(
			iceServers: [String] = ["stun:stun.l.google.com:19302"],
			connectionTimeout: TimeInterval = 15,
			rtcConfiguration: RTCConfiguration? = nil
		) {
			self.iceServers = iceServers
			self.connectionTimeout = connectionTimeout
			if let rtcConfiguration {
				self.rtcConfiguration = rtcConfiguration
			} else {
				let config = RTCConfiguration()
				config.iceServers = [RTCIceServer(urlStrings: iceServers)]
				config.sdpSemantics = .unifiedPlan
				config.continualGatheringPolicy = .gatherContinually
				config.iceCandidatePoolSize = 10
				self.rtcConfiguration = config
			}
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
			maxBitrate: Int = 2_500_000,
			minBitrate: Int = 300_000,
			maxFramerate: Int = 26,
			preferredCodec: String = "VP8"
		) {
			self.maxBitrate = maxBitrate
			self.minBitrate = minBitrate
			self.maxFramerate = maxFramerate
			self.preferredCodec = preferredCodec
		}

		func makeTransceiverInit() -> RTCRtpTransceiverInit {
			let transceiverInit = RTCRtpTransceiverInit()
			transceiverInit.direction = .sendRecv

			let encoding = RTCRtpEncodingParameters()
			encoding.maxBitrateBps = NSNumber(value: maxBitrate)
			encoding.minBitrateBps = NSNumber(value: minBitrate)
			encoding.maxFramerate = NSNumber(value: maxFramerate)
			transceiverInit.sendEncodings = [encoding]

			return transceiverInit
		}

		func configureTransceiver(_ transceiver: RTCRtpTransceiver, factory: RTCPeerConnectionFactory) {
			let supportedCodecs = factory.rtpSenderCapabilities(forKind: "video").codecs
			let preferredCodecName = preferredCodec.uppercased()

			var preferredCodecs: [RTCRtpCodecCapability] = []
			var otherCodecs: [RTCRtpCodecCapability] = []
			var utilityCodecs: [RTCRtpCodecCapability] = []

			for codec in supportedCodecs {
				let codecNameUpper = codec.name.uppercased()
				if codecNameUpper == preferredCodecName {
					preferredCodecs.append(codec)
				} else if codecNameUpper == "RTX" || codecNameUpper == "RED" || codecNameUpper == "ULPFEC" {
					utilityCodecs.append(codec)
				} else {
					otherCodecs.append(codec)
				}
			}

			let sortedCodecs = preferredCodecs + otherCodecs + utilityCodecs
			do {
				try transceiver.setCodecPreferences(sortedCodecs, error: ())
			} catch {
				DecartLogger
					.log(
						"error while setting codec preferences: \(error)",
						level: .error
					)
			}
		}
	}
}
