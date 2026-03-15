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

	public init(
		name: String,
		urlPath: String,
		jobsUrlPath: String? = nil,
		fps: Int,
		width: Int,
		height: Int,
		hasReferenceImage: Bool = false
	) {
		self.name = name
		self.urlPath = urlPath
		self.jobsUrlPath = jobsUrlPath
		self.fps = fps
		self.width = width
		self.height = height
		self.hasReferenceImage = hasReferenceImage
	}
}
