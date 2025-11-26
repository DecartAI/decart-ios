import Foundation
import WebRTC

extension RealtimeManager {
	public func getTransceivers() -> [RTCRtpTransceiver] {
		webRTCClient.transceivers
	}

	public func createAudioSource(constraints: RTCMediaConstraints? = nil) -> RTCAudioSource {
		webRTCClient.createAudioSource(constraints: constraints)
	}

	public func createAudioTrack(source: RTCAudioSource, trackId: String) -> RTCAudioTrack {
		webRTCClient.createAudioTrack(source: source, trackId: trackId)
	}

	public func createVideoSource() -> RTCVideoSource {
		webRTCClient.createVideoSource()
	}

	public func createVideoTrack(source: RTCVideoSource, trackId: String) -> RTCVideoTrack {
		webRTCClient.createVideoTrack(source: source, trackId: trackId)
	}

	public func createLocalVideoTrack() -> (RTCVideoTrack, RTCCameraVideoCapturer) {
		let videoSource = createVideoSource()
		let videoTrack = createVideoTrack(source: videoSource, trackId: UUID().uuidString)
		let videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
		return (videoTrack, videoCapturer)
	}
}
