# Decart iOS SDK

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift 5.9+"></a>
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-15.0+-blue.svg" alt="iOS 15.0+"></a>
  <a href="https://github.com/decartai/decart-ios/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT"></a>
</p>

Native Swift SDK for [Decart AI](https://decart.ai) - Real-time video processing for iOS & macOS.

## Features

- ✅ **Real-time video processing** with WebRTC
- ✅ **Native Swift** with modern concurrency (async/await)
- ✅ **AsyncStream events** for reactive state management
- ✅ **Type-safe API** with compile-time guarantees
- ✅ **iOS 15+** and **macOS 12+** support
- ✅ **SwiftUI** ready

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/decartai/decart-ios.git", from: "0.0.4")
]
```

Or in Xcode:

1. File → Add Package Dependencies
2. Enter: `https://github.com/decartai/decart-ios`
3. Select version and add to target

## Quick Start

```swift
import DecartSDK

// 1. Configure
let config = try DecartConfiguration(
    apiKey: "your-api-key"
)

let client = try createDecartClient(configuration: config)

// 2. Select model
let model = Models.realtime(.lucy_v2v_720p_rt)

// 3. Capture camera
let stream = try await captureLocalStream(
    fps: model.fps,
    width: model.width,
    height: model.height
)

// 4. Create realtime client
let realtimeClient = try client.createRealtimeClient(
    options: RealtimeConnectOptions(
        model: model,
        initialState: ModelState(
            prompt: Prompt(text: "Lego World", enrich: true)
        )
    )
)

// 5. Connect
try await realtimeClient.connect(stream: stream)

// 6. Handle events
Task {
    for await event in realtimeClient.events {
        switch event {
        case .stateChanged(let state):
            print("Connection: \(state)")
        case .remoteStreamReceived(let mediaStream):
            // Handle processed video
            if let videoTrack = mediaStream.videoTracks.first {
                videoTrack.add(remoteVideoView)
            }
        case .error(let error):
            print("Error: \(error)")
        }
    }
}

// 7. Control session
try await realtimeClient.setPrompt("Anime World")
await realtimeClient.setMirror(true)

// 8. Disconnect
await realtimeClient.disconnect()
```

## Examples

See [`Examples/RealtimeExample`](Examples/RealtimeExample) for a complete SwiftUI app demonstrating:

- Camera capture and video rendering
- Real-time prompt updates
- Mirror toggle
- Connection state management
- Error handling

## API Reference

### Core Types

**`DecartConfiguration`**

```swift
let config = try DecartConfiguration(
    baseURL: "https://api3.decart.ai",
    apiKey: "your-api-key"
)
```

**`Models`**

```swift
let model = Models.realtime(.mirage)
// or
let model = Models.realtime(.lucy_v2v_720p_rt)
```

**`RealtimeClient`**

```swift
public class RealtimeClient {
    public let events: AsyncStream<DecartSdkEvent>

    public func connect(stream: RTCMediaStream) async throws
    public func setPrompt(_ prompt: String, enrich: Bool = true) async throws
    public func setMirror(_ enabled: Bool) async
    public func disconnect() async
}
```

**`DecartSdkEvent`**

```swift
public enum DecartSdkEvent {
    case stateChanged(ConnectionState)
    case remoteStreamReceived(RTCMediaStream)
    case error(Error)
}
```

**`ConnectionState`**

```swift
public enum ConnectionState {
    case connecting
    case connected
    case disconnected
}
```

## Requirements

- iOS 15.0+ / macOS 12.0+
- Swift 5.9+
- Xcode 15.0+

## Architecture

The SDK follows Swift best practices:

- **Classes** with weak references for connection management
- **Structs** for value types and configuration
- **AsyncStream** for reactive event streams
- **async/await** for asynchronous operations
- **Error protocol** for proper Swift error handling

## Dependencies

- [WebRTC](https://github.com/stasel/WebRTC) - WebRTC framework for iOS/macOS

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- [Decart Website](https://decart.ai)
- [Platform](https://platform.decart.ai)
- [Documentation](https://docs.platform.decart.ai)
