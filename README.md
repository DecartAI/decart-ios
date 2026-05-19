# Decart iOS SDK

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.2.1-orange.svg" alt="Swift 6.2.1"></a>
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-17.0+-blue.svg" alt="iOS 17.0+"></a>
  <a href="https://github.com/decartai/decart-ios/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT"></a>
</p>

Native Swift SDK for [Decart AI](https://decart.ai) - Real-time video processing and AI generation for iOS & macOS.

## Overview

Decart iOS SDK provides three primary APIs:

- **RealtimeManager** - Real-time video processing with LiveKit streaming, automatic reconnection, and generation tracking
- **QueueClient** - Async video generation via the Queue API (`/v1/jobs/*`) with submit, poll, and download
- **ProcessClient** - Synchronous image generation

All APIs leverage modern Swift concurrency (async/await) with type-safe interfaces and comprehensive error handling.

## Features

- Real-time video processing with LiveKit
- Automatic reconnection with exponential backoff
- Generation tick events for billing/usage tracking
- Async Queue API for video generation (submit → poll → download)
- Synchronous image generation
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
    .package(url: "https://github.com/decartai/decart-ios.git", from: "0.7.0")
]
```

Or in Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/decartai/decart-ios`
3. Select version and add to target

## Usage Examples

### 1. Real-time Video Processing

Stream video with real-time AI processing using LiveKit:

```swift
import DecartSDK
import LiveKit

let config = DecartConfiguration(apiKey: "your-api-key")
let client = DecartClient(decartConfiguration: config)

let model: RealtimeModel = .lucyRestyle2
let modelConfig = Models.realtime(model)

let realtimeManager = try client.createRealtimeManager(
    options: RealtimeConfiguration(
        model: modelConfig,
        initialPrompt: DecartPrompt(text: "Lego World")
    )
)

// Listen to connection events
Task {
    for await state in realtimeManager.events {
        print("State: \(state.connectionState)")
        if let tick = state.generationTick {
            print("Generation: \(tick)s")
        }
        if let sessionId = state.sessionId {
            print("Session: \(sessionId)")
        }
    }
}

// Rebind tracks after automatic reconnection
Task {
    for await newRemoteStream in realtimeManager.remoteStreamUpdates {
        print("Got new remote stream after reconnect")
        // Update your UI with newRemoteStream.videoTrack
    }
}

// Create a LiveKit camera track and connect
let captureOptions = CameraCaptureOptions(
    position: .front,
    dimensions: Dimensions(width: Int32(modelConfig.height), height: Int32(modelConfig.width)),
    fps: modelConfig.fps
)
let videoTrack = LocalVideoTrack.createCameraTrack(name: "video0", options: captureOptions)
let localStream = RealtimeMediaStream(videoTrack: videoTrack, id: .localStream)
let remoteStream = try await realtimeManager.connect(localStream: localStream)

// Update prompt in real-time
realtimeManager.setPrompt(DecartPrompt(text: "Anime World"))

// Cleanup
try? await videoTrack.stop()
await realtimeManager.disconnect()
```

#### Front-camera mirroring

LiveKit's `VideoView` can mirror the local preview without changing the encoded video sent to the server:

```swift
RTCMLVideoViewWrapper(track: localStream.videoTrack, mirror: true)
```

Render the remote stream without mirroring:

```swift
RTCMLVideoViewWrapper(track: remoteStream.videoTrack)
```

#### Output resolution

Realtime models default to a 720p remote stream. Pass `resolution: .p1080` on the `RealtimeConfiguration` to request 1080p instead.

```swift
let realtimeManager = try client.createRealtimeManager(
    options: RealtimeConfiguration(
        model: modelConfig,
        resolution: .p1080 // default: nil (server-side default of 720p)
    )
)
```

### 2. Image-to-Image Generation

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

### 3. Video Generation (Queue API)

Generate videos using the Queue API — handles long-running jobs without HTTP timeouts.

```swift
import DecartSDK

let config = DecartConfiguration(apiKey: "your-api-key")
let client = DecartClient(decartConfiguration: config)

// Video to video
let videoData = try Data(contentsOf: referenceVideoURL)
let fileInput = try FileInput.video(data: videoData)
let input = try VideoToVideoInput(prompt: "Apply anime style", data: fileInput)

let result = try await client.queue.submitAndPoll(model: .lucy_pro_v2v, input: input) { status in
    print("Job \(status.jobId): \(status.status)")
}

switch result {
case .completed(let jobId, let data):
    try data.write(to: outputURL)
case .failed(let jobId, let error):
    print("Failed: \(error)")
}
```

#### Step-by-step control

```swift
// Submit and manage the job manually
let submitResponse = try await client.queue.submit(model: .lucy_pro_v2v, input: input)
print("Job ID: \(submitResponse.jobId)")

// Poll status
let statusResponse = try await client.queue.status(jobId: submitResponse.jobId)

// Download result when complete
if statusResponse.status == .completed {
    let videoData = try await client.queue.result(jobId: submitResponse.jobId)
}
```

#### Check status of any job

```swift
let status = try await client.queue.status(jobId: "some-job-id")
let data = try await client.queue.result(jobId: "some-job-id")
```

### 5. Video Edit (lucy-2.1)

Edit a video with a prompt and optional reference image:

```swift
let videoData = try Data(contentsOf: videoURL)
let videoFile = try FileInput.video(data: videoData)

let input = try VideoEditInput(prompt: "Add snow", data: videoFile)
let result = try await client.queue.submitAndPoll(model: .lucy2_1, input: input)
```

### 6. Video Restyle (lucy-restyle-v2v)

Restyle a video using either a text prompt or a reference image (mutually exclusive):

```swift
let videoData = try Data(contentsOf: videoURL)
let videoFile = try FileInput.video(data: videoData)

// With prompt
let input = try VideoRestyleInput(prompt: "Studio Ghibli style", data: videoFile)

// Or with reference image
let refData = try Data(contentsOf: referenceURL)
let refImage = try FileInput.image(data: refData)
let input = try VideoRestyleInput(data: videoFile, referenceImage: refImage)

let result = try await client.queue.submitAndPoll(model: .lucy_restyle_v2v, input: input)
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

// Create process clients (synchronous image generation)
func createProcessClient(model: ImageModel, input: ImageToImageInput) throws -> ProcessClient

// Queue client for async video generation (recommended)
var queue: QueueClient { get }
```

### QueueClient

```swift
// Submit a job (one overload per input type)
func submit(model: VideoModel, input: VideoToVideoInput) async throws -> JobSubmitResponse
func submit(model: VideoModel, input: VideoEditInput) async throws -> JobSubmitResponse
func submit(model: VideoModel, input: VideoRestyleInput) async throws -> JobSubmitResponse

// Poll / download
func status(jobId: String) async throws -> JobStatusResponse
func result(jobId: String) async throws -> Data

// Submit + poll until terminal state (one overload per input type)
func submitAndPoll(model: VideoModel, input: ..., onStatusChange: ((JobStatusResponse) -> Void)?) async throws -> QueueJobResult
```

### RealtimeManager

```swift
func connect(localStream: RealtimeMediaStream) async throws -> RealtimeMediaStream
func disconnect() async
func setPrompt(_ prompt: DecartPrompt)

// State events (connection, queue position, generation ticks, session ID)
let events: AsyncStream<DecartRealtimeState>

// New remote stream after automatic reconnection
let remoteStreamUpdates: AsyncStream<RealtimeMediaStream>

// Connection states: .idle, .connecting, .connected, .generating, .reconnecting, .disconnected, .error
```

### ProcessClient

```swift
func process() async throws -> Data
```

### Available Models

**Realtime Models:**
- `RealtimeModel.lucy2_1` - Realtime video editing with reference image support
- `RealtimeModel.lucy2_1_vton` - Virtual try-on
- `RealtimeModel.lucyRestyle2` - Realtime video restyling

**Image Models:**
- `ImageModel.lucyImage2` - Image to image

**Video Models:**
- `VideoModel.lucyClip` - Video to video
- `VideoModel.lucy2_1` - Video edit with optional reference image
- `VideoModel.lucy2_1_vton` - Virtual try-on video edit
- `VideoModel.lucyRestyle2` - Video restyle (prompt or reference image)

### Input Types

```swift
// File-based inputs
ImageToImageInput(prompt: String, data: FileInput, seed: Int?)
VideoToVideoInput(prompt: String, data: FileInput, seed: Int?)
VideoEditInput(prompt: String, data: FileInput, referenceImage: FileInput?, seed: Int?)
VideoRestyleInput(prompt: String?, data: FileInput, referenceImage: FileInput?, seed: Int?)

// File input helpers
FileInput.image(data: Data, filename: String)
FileInput.video(data: Data, filename: String)
FileInput.from(data: Data, uniformType: UTType?)
```

### Queue Types

```swift
enum JobStatus: String, Codable {
    case pending, processing, completed, failed
}

struct JobSubmitResponse: Codable { let jobId: String; let status: JobStatus }
struct JobStatusResponse: Codable { let jobId: String; let status: JobStatus }

enum QueueJobResult {
    case completed(jobId: String, data: Data)
    case failed(jobId: String, error: String)
}
```

### RealtimeConfiguration

```swift
RealtimeConfiguration(
    model: ModelDefinition,
    initialPrompt: DecartPrompt,
    connection: ConnectionConfig,  // Optional
    media: MediaConfig             // Optional
)

// Connection config
ConnectionConfig(
    connectionTimeout: TimeInterval,
    reconnectAttempts: Int
)

// Media config
MediaConfig(
    video: VideoConfig
)

// Video config
VideoConfig(
    maxBitrate: Int,     // default: 3_500_000
    maxFramerate: Int,   // default: 30
    preferredCodec: String, // "h264", "vp8", "vp9", or "av1"
    simulcast: Bool      // default: true
)
```

## Requirements

- iOS 17.0+ / macOS 12.0+
- Swift 6.2.1
- Xcode with the Swift 6.2.1 toolchain

## Environment Variables

Configure these in your Xcode scheme (Edit Scheme → Run → Environment Variables):

| Variable | Required | Description |
|----------|----------|-------------|
| `DECART_API_KEY` | Yes | Your Decart API key from [platform.decart.ai](https://platform.decart.ai) |
| `DECART_DEFAULT_PROMPT` | No | Default prompt for realtime sessions (defaults to "Simpsons") |
| `ENABLE_DECART_SDK_DUBUG_LOGS` | No | Set to `YES` to enable verbose SDK logging |

## Dependencies

- [LiveKit Swift SDK](https://github.com/livekit/client-sdk-swift) - Realtime media transport for iOS/macOS

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- [Decart Website](https://decart.ai)
- [Platform](https://platform.decart.ai)
- [Documentation](https://docs.platform.decart.ai)
- [GitHub Issues](https://github.com/decartai/decart-ios/issues)
