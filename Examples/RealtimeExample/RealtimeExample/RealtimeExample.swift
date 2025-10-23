import SwiftUI
import DecartSDK
import WebRTC
import Combine

@main
struct RealtimeExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = RealtimeViewModel()
    
    var body: some View {
        ZStack {
            // Remote video background
            VideoView(videoView: viewModel.remoteVideoView)
                .background(Color.black)
                .edgesIgnoringSafeArea(.all)
            
            // UI overlay
            VStack(spacing: 16) {
                // Top bar
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Decart Realtime")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(viewModel.connectionState)
                            .font(.caption)
                            .foregroundColor(viewModel.isConnected ? .green : .white)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.black.opacity(0.6))
                
                Spacer()
                
                // Local video preview
                if viewModel.connectionState != "Disconnected" {
                    HStack {
                        Spacer()
                        VideoView(videoView: viewModel.localVideoView)
                            .frame(width: 120, height: 160)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white, lineWidth: 2))
                            .padding()
                    }
                }
                
                // Controls
                VStack(spacing: 12) {
                    if let error = viewModel.lastError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(8)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(8)
                    }
                    
                    HStack(spacing: 12) {
                        TextField("Prompt", text: $viewModel.promptText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            // .disabled(!viewModel.isConnected)
                        
                        Button(action: {
                            Task {
                                await viewModel.setPrompt()
                            }
                        }) {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(.white)
                                .padding(12)
                                .background(viewModel.isConnected ? Color.blue : Color.gray)
                                .cornerRadius(8)
                        }
                        // .disabled(!viewModel.isConnected)
                    }
                    
                    HStack(spacing: 12) {
                        Toggle("Mirror", isOn: $viewModel.mirror)
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                            // .disabled(!viewModel.isConnected)
                        
                        Spacer()
                        
                        Button(action: {
                            Task {
                                await viewModel.connect()
                            }
                        }) {
                            Text(viewModel.isConnected ? "Disconnect" : "Connect")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(viewModel.isConnected ? Color.red : Color.green)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .background(Color.black.opacity(0.8))
                .cornerRadius(16)
                .padding()
            }
        }
    }
}

// SwiftUI wrapper for RTCMTLVideoView
struct VideoView: UIViewRepresentable {
    let videoView: RTCMTLVideoView
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        videoView.contentMode = .scaleAspectFill
        return videoView
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // No updates needed
    }
}

private enum Config {
    static let apiKey = "testrpQWXnyFDQCiXcXAeBZgWwnfEiptgxSPOaPjhRcsxuKuguLLvgEpiqmOiJGjXxZY"
    static let baseURL = "https://api3.decart.ai"
    static let defaultPrompt = "Turn the figure into a fantasy figure"
}

@MainActor
class RealtimeViewModel: ObservableObject {
    @Published var connectionState: String = "Disconnected"
    @Published var promptText: String = Config.defaultPrompt
    @Published var mirror: Bool = false {
        didSet {
            if mirror != oldValue {
                Task {
                    await setMirror(mirror)
                }
            }
        }
    }
    @Published var lastError: String?
    
    var isConnected: Bool {
        connectionState == "Connected"
    }
    
    private var client: RealtimeClient?
    private var cancellables = Set<AnyCancellable>()
    private var localStream: RTCMediaStream?
    private var remoteVideoTrack: RTCVideoTrack?
    private var videoCapturer: RTCCameraVideoCapturer?
    private var peerConnectionFactory: RTCPeerConnectionFactory?
    
    // Video views for rendering
    let remoteVideoView: RTCMTLVideoView = {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFill
        return view
    }()
    
    let localVideoView: RTCMTLVideoView = {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFill
        return view
    }()
    
    func connect() async {
        print("🔵 Connect button tapped")
        if isConnected {
            print("🔵 Already connected, disconnecting first...")
            await disconnect()
            return
        }

        connectionState = "Connecting"
        lastError = nil
        
        do {
            print("🔵 Creating configuration...")
            print("🔵 Base URL: \(Config.baseURL)")
            print("🔵 API Key: \(String(Config.apiKey.prefix(20)))...")

            if Config.apiKey == "your-api-key" {
                print("❌ API key is not set, please set it in Config.apiKey")
                lastError = "API key is not set, please set it in Config.apiKey"
                return
            }
            
            let configuration = try DecartConfiguration(
                baseURL: Config.baseURL,
                apiKey: Config.apiKey
            )
            
            print("🔵 Creating Decart client...")
            let decartClient = try createDecartClient(configuration: configuration)
            
            let model = Models.realtime(.lucy_v2v_720p_rt)
            print("🔵 Using model: \(model.name)")
            print("🔵 Model config - FPS: \(model.fps), Size: \(model.width)x\(model.height)")
            print("🔵 Expected WebRTC URL: wss://api3.decart.ai\(model.urlPath)?api_key=...&model=\(model.name)")
            
            print("🔵 Starting camera capture...")
            localStream = try await captureLocalStream(
                fps: model.fps,
                width: model.width,
                height: model.height
            )
            
            guard let stream = localStream else {
                print("❌ Failed to get local stream")
                lastError = "Failed to get local stream"
                return
            }
            
            print("✅ Camera captured successfully")
            print("🔵 Video tracks: \(stream.videoTracks.count), Audio tracks: \(stream.audioTracks.count)")
            
            // Attach local video track to preview
            if let localVideoTrack = stream.videoTracks.first {
                print("🔵 Attaching local video to preview...")
                localVideoTrack.add(localVideoView)
            }
            
            print("🔵 Connecting to WebRTC...")
            let realtimeClient = try await decartClient.realtime.connect(
                stream: stream,
                options: RealtimeConnectOptions(
                    model: model,
                    onRemoteStream: { [weak self] mediaStream in
                        print("🟢 REMOTE STREAM RECEIVED!")
                        print("🟢 Remote video tracks: \(mediaStream.videoTracks.count)")
                        Task { @MainActor in
                            guard let self = self,
                                  let videoTrack = mediaStream.videoTracks.first else {
                                print("⚠️ No video track in remote stream")
                                return
                            }
                            print("🟢 Attaching remote video to view...")
                            self.remoteVideoTrack = videoTrack
                            videoTrack.add(self.remoteVideoView)
                            print("✅ Remote video attached!")
                        }
                    },
                    initialState: ModelState(
                        prompt: Prompt(text: promptText, enrich: true),
                        mirror: mirror
                    )
                )
            )
            
            print("✅ WebRTC connection established!")
            self.client = realtimeClient
            
            realtimeClient.connectionStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    print("🟢 Connection state changed: \(state)")
                    self?.handleConnectionState(state)
                }
                .store(in: &cancellables)
            
            realtimeClient.errorPublisher
                .sink { [weak self] error in
                    print("❌ Error received: \(error.localizedDescription)")
                    self?.lastError = error.localizedDescription
                }
                .store(in: &cancellables)
        } catch {
            print("❌ Connection failed with error: \(error.localizedDescription)")
            print("❌ Error details: \(error)")
            lastError = error.localizedDescription
            connectionState = "Disconnected"
        }
    }
    
    func disconnect() async {
        // Stop camera
        if let capturer = videoCapturer {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                capturer.stopCapture { continuation.resume() }
            }
        }
        
        // Remove video tracks
        remoteVideoTrack?.remove(remoteVideoView)
        localStream?.videoTracks.first?.remove(localVideoView)
        
        // Cleanup
        await client?.disconnect()
        client = nil
        connectionState = "Disconnected"
        videoCapturer = nil
        remoteVideoTrack = nil
        localStream = nil
        peerConnectionFactory = nil
        
        RTCCleanupSSL()
    }
    
    func setPrompt() async {
        guard let client = client else { return }
        
        do {
            try await client.setPrompt(promptText, enrich: true)
        } catch {
            lastError = error.localizedDescription
        }
    }
     
    func setMirror(_ enabled: Bool) async {
        guard let client = client else { return }
        await client.setMirror(enabled)
    }
    
    private func handleConnectionState(_ state: ConnectionState) {
        print("🔄 Handling connection state: \(state)")
        switch state {
        case .connecting:
            connectionState = "Connecting"
            print("📡 Status updated to: Connecting")
        case .connected:
            connectionState = "Connected"
            print("✅ Status updated to: Connected")
        case .disconnected:
            connectionState = "Disconnected"
            print("⚠️ Status updated to: Disconnected")
        }
    }
    
    private func captureLocalStream(fps: Int, width: Int, height: Int) async throws -> RTCMediaStream {
        print("📹 Initializing WebRTC SSL...")
        RTCInitializeSSL()
        
        print("📹 Creating peer connection factory...")
        let factory = RTCPeerConnectionFactory()
        self.peerConnectionFactory = factory
        
        let videoSource = factory.videoSource()
        
        func cameraError(_ message: String) -> DecartError {
            print("❌ Camera error: \(message)")
            return DecartError.webRTCError(NSError(domain: "Camera", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
        
        #if targetEnvironment(simulator)
        print("❌ Running in simulator!")
        throw cameraError("Simulator not supported - use real device")
        #else
        print("📹 Creating camera capturer...")
        let capturer = RTCCameraVideoCapturer(delegate: videoSource)
        self.videoCapturer = capturer
        
        let devices = RTCCameraVideoCapturer.captureDevices()
        print("📹 Available cameras: \(devices.count)")
        for (i, device) in devices.enumerated() {
            print("📹   Camera \(i): \(device.localizedName) - Position: \(device.position.rawValue)")
        }
        
        guard let frontCamera = devices.first(where: { $0.position == .back }) else {
            throw cameraError("No front camera found")
        }
        print("📹 Using front camera: \(frontCamera.localizedName)")
        
        let formats = RTCCameraVideoCapturer.supportedFormats(for: frontCamera)
        print("📹 Available formats: \(formats.count)")
        
        guard let format = formats.first(where: { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width >= width && dimensions.height >= height
        }) ?? formats.first else {
            throw cameraError("No suitable camera format")
        }
        
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        print("📹 Selected format: \(dimensions.width)x\(dimensions.height)")
        
        guard let fpsRange = format.videoSupportedFrameRateRanges.first(where: { range in
            return range.maxFrameRate >= Double(fps)
        }) ?? format.videoSupportedFrameRateRanges.first else {
            throw cameraError("No suitable FPS range")
        }
        
        let targetFps = Int(fpsRange.maxFrameRate)
        print("📹 Target FPS: \(targetFps) (requested: \(fps))")
        
        print("📹 Starting camera capture...")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            capturer.startCapture(with: frontCamera, format: format, fps: targetFps) { error in
                if let error = error {
                    print("❌ Camera capture failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    print("✅ Camera capture started successfully")
                    continuation.resume()
                }
            }
        }
        #endif
        
        let videoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
        videoTrack.isEnabled = true
        
        let stream = factory.mediaStream(withStreamId: "stream0")
        stream.addVideoTrack(videoTrack)
        
        return stream
    }
}
