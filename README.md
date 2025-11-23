# Decart iOS SDK

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift 5.9+"></a>
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-15.0+-blue.svg" alt="iOS 15.0+"></a>
  <a href="https://github.com/decartai/decart-ios/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT"></a>
</p>

Native Swift SDK for [Decart AI](https://decart.ai) - Real-time video processing and AI generation for iOS & macOS.

## Overview

Decart iOS SDK provides two primary APIs:

- **RealtimeClient** - Real-time video processing with WebRTC streaming
- **ProcessClient** - Batch image and video generation

Both APIs leverage modern Swift concurrency (async/await) with type-safe interfaces and comprehensive error handling.

## Features

- ✅ **Real-time video processing** with WebRTC
- ✅ **Batch image and video generation**
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

## Usage Examples

### 1. Real-time Video Processing

Stream video with real-time AI processing using WebRTC:

```swift
import DecartSDK
import WebRTC

// Configure SDK
let config = DecartConfiguration(apiKey: "your-api-key")
let client = DecartClient(decartConfiguration: config)

// Create realtime client
let model = Models.realtime(.mirage)
let realtimeClient = try client.createRealtimeClient(
    options: RealtimeConfiguration(
        model: model,
        initialState: ModelState(prompt: Prompt(text: "Lego World"))
    )
)

// Capture local camera stream
let (localStream, cameraCapturer) = try await RealtimeCameraCapture.captureLocalCameraStream(
    realtimeClient: realtimeClient,
    cameraFacing: .front
)

// Connect and receive remote stream
let remoteStream = try await realtimeClient.connect(localStream: localStream)
remoteStream.videoTrack.add(videoRenderer)

// Listen to connection events
Task {
    for await state in realtimeClient.events {
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
realtimeClient.setPrompt(Prompt(text: "Anime World"))

// Cleanup
defer {
    cameraCapturer.stopCapture(completionHandler: {})
    Task { await realtimeClient.disconnect() }
}
```

### 2. Text-to-Image Generation

Generate images from text prompts:

```swift
import DecartSDK

// Configure SDK
let config = DecartConfiguration(apiKey: "your-api-key")
let client = DecartClient(decartConfiguration: config)

// Create input
let input = TextToImageInput(prompt: "Retro robot in neon city")

// Create process client
let processClient = try client.createProcessClient(
    model: .lucy_pro_t2i,
    input: input
)

// Generate image
let imageData = try await processClient.process()
let image = UIImage(data: imageData)
```

### 3. Image-to-Video Generation

Generate videos from reference images:

```swift
import DecartSDK
import UniformTypeIdentifiers

// Configure SDK
let config = DecartConfiguration(apiKey: "your-api-key")
let client = DecartClient(decartConfiguration: config)

// Load reference image
let imageData = try Data(contentsOf: referenceImageURL)
let fileInput = try FileInput.from(data: imageData, uniformType: .jpeg)

// Create input
let input = ImageToVideoInput(prompt: "Make it dance", data: fileInput)

// Create process client
let processClient = try client.createProcessClient(
    model: .lucy_pro_i2v,
    input: input
)

// Generate video
let videoData = try await processClient.process()
try videoData.write(to: outputURL)
```

## API Reference

### Core Configuration

#### DecartConfiguration

Initialize the SDK with your API credentials:

```swift
let config = DecartConfiguration(
    baseURL: "https://api3.decart.ai", // Optional, defaults to api3.decart.ai
    apiKey: "your-api-key"
)
```

#### DecartClient

Main entry point for creating realtime and process clients:

```swift
let client = DecartClient(decartConfiguration: config)
```

### RealtimeClient

Real-time video streaming with WebRTC.

#### Methods

```swift
func createRealtimeClient(options: RealtimeConfiguration) throws -> RealtimeClient
func connect(localStream: RealtimeMediaStream) async throws -> RealtimeMediaStream
func disconnect() async
func setPrompt(_ prompt: Prompt)
```

#### Events

```swift
let events: AsyncStream<DecartRealtimeConnectionState>

// States: .idle, .connecting, .connected, .disconnected, .error
```

#### Available Models

```swift
Models.realtime(.mirage)
Models.realtime(.mirage_v2)
Models.realtime(.lucy_v2v_720p_rt)
```

### ProcessClient

Batch image and video generation.

#### Methods

```swift
func createProcessClient(model: ImageModel, input: TextToImageInput) throws -> ProcessClient
func createProcessClient(model: ImageModel, input: ImageToImageInput) throws -> ProcessClient
func createProcessClient(model: VideoModel, input: TextToVideoInput) throws -> ProcessClient
func createProcessClient(model: VideoModel, input: ImageToVideoInput) throws -> ProcessClient
func createProcessClient(model: VideoModel, input: VideoToVideoInput) throws -> ProcessClient

func process() async throws -> Data
```

#### Available Models

**Image Models:**
- `.lucy_pro_t2i` - Text to image
- `.lucy_pro_i2i` - Image to image

**Video Models:**
- `.lucy_pro_t2v` - Text to video
- `.lucy_pro_i2v` - Image to video
- `.lucy_pro_v2v` - Video to video
- `.lucy_dev_i2v` - Image to video (dev)
- `.lucy_dev_v2v` - Video to video (dev)

### Input Types

```swift
// Text-based inputs
TextToImageInput(prompt: String, seed: Int? = nil, resolution: ProResolution? = .res720p)
TextToVideoInput(prompt: String, seed: Int? = nil, resolution: ProResolution? = .res720p)

// File-based inputs
ImageToImageInput(prompt: String, data: FileInput, seed: Int? = nil)
ImageToVideoInput(prompt: String, data: FileInput, seed: Int? = nil)
VideoToVideoInput(prompt: String, data: FileInput, seed: Int? = nil)

// File input helpers
FileInput.image(data: Data, filename: String = "image.jpg")
FileInput.video(data: Data, filename: String = "video.mp4")
FileInput.from(data: Data, uniformType: UTType?)
```

## Requirements

- iOS 15.0+ / macOS 12.0+
- Swift 5.9+
- Xcode 15.0+

## Architecture

The SDK follows Swift best practices:

- **Value types** (structs) for configuration and data models
- **Reference types** (classes) for connection management
- **AsyncStream** for reactive event streams
- **async/await** for asynchronous operations
- **Structured concurrency** with Task-based cancellation
- **Type-safe protocols** for proper Swift error handling

## Dependencies

- [WebRTC](https://github.com/stasel/WebRTC) - WebRTC framework for iOS/macOS

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- [Decart Website](https://decart.ai)
- [Platform](https://platform.decart.ai)
- [Documentation](https://docs.platform.decart.ai)
- [GitHub Issues](https://github.com/decartai/decart-ios/issues)
