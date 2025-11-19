import Foundation
import WebRTC

extension RealtimeEngine {
	// MARK: - Media Factory Methods

	public func getTransceivers() -> [RTCRtpTransceiver] {
		webRTCService.peerConnection.transceivers
	}

	public func createAudioSource(constraints: RTCMediaConstraints? = nil) -> RTCAudioSource {
		webRTCService.factory.audioSource(with: constraints)
	}

	public func createAudioTrack(source: RTCAudioSource, trackId: String) -> RTCAudioTrack {
		webRTCService.factory.audioTrack(with: source, trackId: trackId)
	}

	public func createVideoSource() -> RTCVideoSource {
		webRTCService.factory.videoSource()
	}

	public func createVideoTrack(source: RTCVideoSource, trackId: String) -> RTCVideoTrack {
		webRTCService.factory.videoTrack(with: source, trackId: trackId)
	}

	public func createLocalVideoTrack() -> (RTCVideoTrack, RTCCameraVideoCapturer) {
		let videoSource = createVideoSource()
		let videoTrack = createVideoTrack(source: videoSource, trackId: UUID().uuidString)
		let videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
		return (videoTrack, videoCapturer)
	}
}
