import Foundation

public struct Prompt: Sendable {
	public let text: String
	public let enrich: Bool

	public init(text: String, enrich: Bool = true) {
		self.text = text
		self.enrich = enrich
	}
}

public struct ModelState: Sendable {
	public let prompt: Prompt

	public init(prompt: Prompt) {
		self.prompt = prompt
	}
}
