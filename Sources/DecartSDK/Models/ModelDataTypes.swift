//
//  ModelDataTypes.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 05/11/2025.
//

public struct ModelDefinition: Sendable {
	public let name: String
	public let urlPath: String
	public let fps: Int
	public let width: Int
	public let height: Int

	public init(name: String, urlPath: String, fps: Int, width: Int, height: Int) {
		self.name = name
		self.urlPath = urlPath
		self.fps = fps
		self.width = width
		self.height = height
	}
}
