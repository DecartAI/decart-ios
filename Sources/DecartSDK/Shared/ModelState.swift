import Foundation

public struct Prompt {
    public let text: String
    public let enrich: Bool

    public init(text: String, enrich: Bool = true) {
        self.text = text
        self.enrich = enrich
    }
}

public struct ModelState {
    public let prompt: Prompt?
    public let mirror: Bool

    public init(prompt: Prompt? = nil, mirror: Bool = false) {
        self.prompt = prompt
        self.mirror = mirror
    }
}
