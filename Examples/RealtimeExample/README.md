# Realtime Example

A complete SwiftUI application demonstrating the Decart iOS SDK.

## Features

- Real-time video processing
- Camera capture with RTCCameraVideoCapturer
- Prompt control with live updates
- Mirror toggle
- Connection state management
- Error handling
- Picture-in-picture video preview
- Full-screen remote video display

## Running the Example

1. Open `RealtimeExample.xcodeproj` in Xcode
2. Update `Config.apiKey` in `RealtimeExample.swift` with your Decart API key
3. Select a target device (iPhone/iPad - **simulator not supported** for camera)
4. Build and run (⌘R)

## Code Structure

**`RealtimeExample.swift`** - Complete app in a single file (368 lines)

- `RealtimeExampleApp` - App entry point
- `ContentView` - Main UI with video and controls
- `VideoView` - UIViewRepresentable wrapper for RTCMTLVideoView
- `RealtimeViewModel` - Business logic and SDK integration
- `Config` - Configuration (API key, base URL, default prompt)

## Requirements

- iOS 15.0+
- Xcode 15.0+
- **Physical device** (camera required, simulator not supported)
- Decart API key

## Key Concepts

### Camera Capture

```swift
let stream = try await captureLocalStream(
    fps: model.fps,
    width: model.width,
    height: model.height
)
```

### Connecting to Realtime API

```swift
let client = try await decartClient.realtime.connect(
    stream: stream,
    options: RealtimeConnectOptions(
        model: model,
        onRemoteStream: { mediaStream in
            // Attach to video view
        },
        initialState: ModelState(
            prompt: Prompt(text: "Lego World", enrich: true),
            mirror: false
        )
    )
)
```

### State Management with Combine

```swift
client.connectionStatePublisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] state in
        self?.handleConnectionState(state)
    }
    .store(in: &cancellables)
```

### Video Rendering

```swift
// SwiftUI wrapper for RTCMTLVideoView
struct VideoView: UIViewRepresentable {
    let videoView: RTCMTLVideoView
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        videoView.contentMode = .scaleAspectFill
        return videoView
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {}
}
```

## Learn More

- [Main README](../../README.md)
- [Decart Website](https://decart.ai)
- [Platform](https://platform.decart.ai)
- [Documentation](https://docs.platform.decart.ai)
