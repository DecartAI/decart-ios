//
//  RTCPeerConnection+Ext.swift
//  DecartSDK
//
//  Created by Alon Bar-el on 04/11/2025.
//
import WebRTC

extension RTCPeerConnection {
	func offer(for constraints: RTCMediaConstraints) async throws -> RTCSessionDescription? {
		try await withCheckedThrowingContinuation { continuation in
			self.offer(for: constraints) { sdp, error in
				if let error = error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume(returning: sdp)
				}
			}
		}
	}

	func answer(for constraints: RTCMediaConstraints) async throws -> RTCSessionDescription? {
		try await withCheckedThrowingContinuation { continuation in
			self.answer(for: constraints) { sdp, error in
				if let error = error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume(returning: sdp)
				}
			}
		}
	}

	func setLocalDescription(_ sdp: RTCSessionDescription) async throws {
		try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<Void, Error>) in
			self.setLocalDescription(sdp) { error in
				if let error = error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			}
		}
	}

	func setRemoteDescription(_ sdp: RTCSessionDescription) async throws {
		try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<Void, Error>) in
			self.setRemoteDescription(sdp) { error in
				if let error = error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			}
		}
	}

	func add(_ candidate: RTCIceCandidate) async throws {
		try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<Void, Error>) in
			self.add(candidate) { error in
				if let error = error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			}
		}
	}
}
