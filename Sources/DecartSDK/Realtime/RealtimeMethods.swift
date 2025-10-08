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
