//
//  ModelDataTypes.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 05/11/2025.
//

public struct ModelDefinition: Sendable {
	public let name: String
	public let urlPath: String
	public let jobsUrlPath: String?
	public let fps: Int
	public let width: Int
	public let height: Int
	public let hasReferenceImage: Bool
	/// Realtime compute tiers this model can be served from (see `Speed`). Empty
	/// for models that only offer standard mode; `speed` is ignored server-side for
	/// those.
	public let supportedSpeeds: [Speed]

	public init(
		name: String,
		urlPath: String,
		jobsUrlPath: String? = nil,
		fps: Int,
		width: Int,
		height: Int,
		hasReferenceImage: Bool = false,
		supportedSpeeds: [Speed] = []
	) {
		self.name = name
		self.urlPath = urlPath
		self.jobsUrlPath = jobsUrlPath
		self.fps = fps
		self.width = width
		self.height = height
		self.hasReferenceImage = hasReferenceImage
		self.supportedSpeeds = supportedSpeeds
	}
}
