# Decart iOS SDK

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift 5.9+"></a>
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-15.0+-blue.svg" alt="iOS 15.0+"></a>
  <a href="https://github.com/decartai/decart-ios/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT"></a>
</p>

Native Swift SDK for [Decart AI](https://decart.ai) - Real-time video processing and AI generation for iOS & macOS.

## Overview

Decart iOS SDK provides two primary APIs:

- **RealtimeManager** - Real-time video processing with WebRTC streaming
- **ProcessClient** - Batch image and video generation

Both APIs leverage modern Swift concurrency (async/await) with type-safe interfaces and comprehensive error handling.

## Features

- Real-time video processing with WebRTC
- Batch image and video generation
- Native Swift with modern concurrency (async/await)
- AsyncStream events for reactive state management
- Type-safe API with compile-time guarantees
- iOS 15+ and macOS 12+ support
- SwiftUI ready

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

## Usage Examples

### 1. Real-time Video Processing

Stream video with real-time AI processing using WebRTC:

```swift
import DecartSDK

let config = DecartConfiguration(apiKey: "your-api-key")
let client = DecartClient(decartConfiguration: config)

let model = Models.realtime(.mirage)
let realtimeManager = try client.createRealtimeManager(
    options: RealtimeConfiguration(
        model: model,
        initialState: ModelState(prompt: Prompt(text: "Lego World"))
    )
)

// Create video source and camera capture
let videoSource = realtimeManager.createVideoSource()
let capture = RealtimeCapture(model: model, videoSource: videoSource)
try await capture.startCapture()

// Create local stream and connect
let videoTrack = realtimeManager.createVideoTrack(source: videoSource, trackId: "video0")
let localStream = RealtimeMediaStream(videoTrack: videoTrack, id: .localStream)
let remoteStream = try await realtimeManager.connect(localStream: localStream)

// Listen to connection events
Task {
    for await state in realtimeManager.events {
        switch state {
        case .connected:
            print("Connected")
        case .disconnected:
            print("Disconnected")
        case .error:
            print("Connection error")
        default:
            break
        }
    }
}

// Update prompt in real-time
realtimeManager.setPrompt(Prompt(text: "Anime World"))

// Cleanup
await capture.stopCapture()
await realtimeManager.disconnect()
```

### 2. Text-to-Image Generation

Generate images from text prompts:

```swift
import DecartSDK

let config = DecartConfiguration(apiKey: "your-api-key")
let client = DecartClient(decartConfiguration: config)

let input = try TextToImageInput(prompt: "Retro robot in neon city")

let processClient = try client.createProcessClient(
    model: .lucy_pro_t2i,
    input: input
)

let imageData = try await processClient.process()
let image = UIImage(data: imageData)
```

### 3. Image-to-Image Generation

Transform images with AI:

```swift
import DecartSDK

let config = DecartConfiguration(apiKey: "your-api-key")
let client = DecartClient(decartConfiguration: config)

let imageData = try Data(contentsOf: referenceImageURL)
let fileInput = try FileInput.image(data: imageData)

let input = try ImageToImageInput(prompt: "Make it cyberpunk", data: fileInput)

let processClient = try client.createProcessClient(
    model: .lucy_pro_i2i,
    input: input
)

let resultData = try await processClient.process()
let image = UIImage(data: resultData)
```

### 4. Image-to-Video Generation

Generate videos from reference images:

```swift
import DecartSDK

let config = DecartConfiguration(apiKey: "your-api-key")
let client = DecartClient(decartConfiguration: config)

let imageData = try Data(contentsOf: referenceImageURL)
let fileInput = try FileInput.image(data: imageData)

let input = try ImageToVideoInput(prompt: "Make it dance", data: fileInput)

let processClient = try client.createProcessClient(
    model: .lucy_pro_i2v,
    input: input
)

let videoData = try await processClient.process()
try videoData.write(to: outputURL)
```

### 5. Video-to-Video Generation

Transform videos with AI:

```swift
import DecartSDK

let config = DecartConfiguration(apiKey: "your-api-key")
let client = DecartClient(decartConfiguration: config)

let videoData = try Data(contentsOf: referenceVideoURL)
let fileInput = try FileInput.video(data: videoData)

let input = try VideoToVideoInput(prompt: "Apply anime style", data: fileInput)

let processClient = try client.createProcessClient(
    model: .lucy_pro_v2v,
    input: input
)

let resultData = try await processClient.process()
try resultData.write(to: outputURL)
```

## API Reference

### DecartConfiguration

```swift
let config = DecartConfiguration(
    baseURL: "https://api3.decart.ai",  // Optional
    apiKey: "your-api-key"
)
```

### DecartClient

```swift
let client = DecartClient(decartConfiguration: config)

// Create realtime manager
func createRealtimeManager(options: RealtimeConfiguration) throws -> RealtimeManager

// Create process clients
func createProcessClient(model: ImageModel, input: TextToImageInput) throws -> ProcessClient
func createProcessClient(model: ImageModel, input: ImageToImageInput) throws -> ProcessClient
func createProcessClient(model: VideoModel, input: TextToVideoInput) throws -> ProcessClient
func createProcessClient(model: VideoModel, input: ImageToVideoInput) throws -> ProcessClient
func createProcessClient(model: VideoModel, input: VideoToVideoInput) throws -> ProcessClient
```

### RealtimeManager

```swift
func connect(localStream: RealtimeMediaStream) async throws -> RealtimeMediaStream
func disconnect() async
func setPrompt(_ prompt: Prompt)
func getStats() async -> RTCStatisticsReport?

let events: AsyncStream<DecartRealtimeConnectionState>
// States: .idle, .connecting, .connected, .disconnected, .error
```

### ProcessClient

```swift
func process() async throws -> Data
```

### Available Models

**Realtime Models:**
- `RealtimeModel.mirage`
- `RealtimeModel.mirage_v2`
- `RealtimeModel.lucy_v2v_720p_rt`

**Image Models:**
- `ImageModel.lucy_pro_t2i` - Text to image
- `ImageModel.lucy_pro_i2i` - Image to image

**Video Models:**
- `VideoModel.lucy_pro_t2v` - Text to video
- `VideoModel.lucy_pro_i2v` - Image to video
- `VideoModel.lucy_pro_v2v` - Video to video
- `VideoModel.lucy_dev_i2v` - Image to video (dev)
- `VideoModel.lucy_fast_v2v` - Fast video to video

### Input Types

```swift
// Text-based inputs
TextToImageInput(prompt: String, seed: Int?, resolution: ProResolution?)
TextToVideoInput(prompt: String, seed: Int?, resolution: ProResolution?)

// File-based inputs
ImageToImageInput(prompt: String, data: FileInput, seed: Int?)
ImageToVideoInput(prompt: String, data: FileInput, seed: Int?)
VideoToVideoInput(prompt: String, data: FileInput, seed: Int?)

// File input helpers
FileInput.image(data: Data, filename: String)
FileInput.video(data: Data, filename: String)
FileInput.from(data: Data, uniformType: UTType?)
```

### RealtimeConfiguration

```swift
RealtimeConfiguration(
    model: ModelDefinition,
    initialState: ModelState,
    connection: ConnectionConfig,  // Optional
    media: MediaConfig             // Optional
)

// Connection config
ConnectionConfig(
    iceServers: [String],
    connectionTimeout: Int32,
    pingInterval: Int32
)

// Media config
MediaConfig(
    video: VideoConfig
)

// Video config
VideoConfig(
    maxBitrate: Int,
    minBitrate: Int,
    maxFramerate: Int,
    preferredCodec: String  // "VP8" or "H264"
)
```

## Requirements

- iOS 15.0+ / macOS 12.0+
- Swift 5.9+
- Xcode 15.0+

## Dependencies

- [WebRTC](https://github.com/nickkjordan/WebRTC) - WebRTC framework for iOS/macOS

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- [Decart Website](https://decart.ai)
- [Platform](https://platform.decart.ai)
- [Documentation](https://docs.platform.decart.ai)
- [GitHub Issues](https://github.com/decartai/decart-ios/issues)
