import Foundation

public struct DecartPrompt: Sendable {
	public let text: String
	public let enrich: Bool
	// for lucy 14b we must send a ref image with text prompt
	public let referenceImageBase64: String?

	public init(text: String, referenceImageBase64: String? = nil, enrich: Bool = false) {
		self.text = text
		self.referenceImageBase64 = referenceImageBase64
		self.enrich = enrich
	}
}
