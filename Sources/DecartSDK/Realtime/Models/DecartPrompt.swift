import Foundation

public struct DecartPrompt: Sendable {
	public let text: String
	public let enrich: Bool
	// for lucy 14b we must send a ref image with text prompt
	public let referenceImageData: Data?

	public init(text: String, referenceImageData: Data? = nil, enrich: Bool = false) {
		self.text = text
		self.referenceImageData = referenceImageData
		self.enrich = enrich
	}
}
