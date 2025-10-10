import Foundation

struct RealtimeMethods {
    private let webrtcManager: WebRTCManager

    init(webrtcManager: WebRTCManager) {
        self.webrtcManager = webrtcManager
    }

    func enrichPrompt(_ prompt: String) async throws -> String {
        throw DecartError.invalidOptions("enrichPrompt not implemented")
    }

    func setPrompt(_ prompt: String, enrich: Bool = true) async throws {
        guard !prompt.isEmpty else {
            throw DecartError.invalidInput("Prompt must not be empty")
        }

        await webrtcManager.sendMessage(.prompt(PromptMessage(prompt: prompt)))
    }

    func setMirror(_ enabled: Bool) async {
        let rotateY = enabled ? 2 : 0
        await webrtcManager.sendMessage(.switchCamera(SwitchCameraMessage(rotateY: rotateY)))
    }
}

public struct PeerConnectionConfig {
    public let maxBitrate: Int
    public let minBitrate: Int
    public let maxFramerate: Int

    public init(maxBitrate: Int = 3800_000, minBitrate: Int = 800_000, maxFramerate: Int = 30) {
        self.maxBitrate = maxBitrate
        self.minBitrate = minBitrate
        self.maxFramerate = maxFramerate
    }
}
