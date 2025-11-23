import Foundation
import WebRTC

extension RealtimeClient {
	// MARK: - Media Factory Methods

	public func getTransceivers() -> [RTCRtpTransceiver] {
		webRTCManager.peerConnection.transceivers
	}

	public func createAudioSource(constraints: RTCMediaConstraints? = nil) -> RTCAudioSource {
		webRTCManager.factory.audioSource(with: constraints)
	}

	public func createAudioTrack(source: RTCAudioSource, trackId: String) -> RTCAudioTrack {
		webRTCManager.factory.audioTrack(with: source, trackId: trackId)
	}

	public func createVideoSource() -> RTCVideoSource {
		webRTCManager.factory.videoSource()
	}

	public func createVideoTrack(source: RTCVideoSource, trackId: String) -> RTCVideoTrack {
		webRTCManager.factory.videoTrack(with: source, trackId: trackId)
	}

	public func createLocalVideoTrack() -> (RTCVideoTrack, RTCCameraVideoCapturer) {
		let videoSource = createVideoSource()
		let videoTrack = createVideoTrack(source: videoSource, trackId: UUID().uuidString)
		let videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
		return (videoTrack, videoCapturer)
	}
}

