import Foundation
import Network
import Security

/// Native STUN-over-UDP reachability probe — the iOS analog of the JS SDK's
/// throwaway `RTCPeerConnection` ICE gather. Sends a STUN Binding Request (RFC
/// 5389) to a public STUN server over UDP and classifies the transport from the
/// response:
///
/// - Binding Success Response (transaction-ID match) → `.udp` + measured RTT
///   (the server-reflexive / `srflx` signal the JS probe extracts).
/// - Reached a usable socket but no valid response before the timeout → `.relay`
///   (UDP egress to STUN is blocked → the session will need TURN).
/// - Never reached a usable socket / path failed → `.failed`.
///
/// Never throws — every failure mode resolves to a metrics value, matching the
/// JS probe's catch-all behaviour. No new dependencies (Foundation + Network).
enum STUNProbe {
	static func probe(server: STUNServer, timeoutMs: Int) async -> ConnectivityMetrics {
		if Task.isCancelled { return ConnectivityMetrics(transport: .failed, rttMs: nil) }
		return await STUNProbeSession(server: server, timeoutMs: timeoutMs).run()
	}
}

private final class STUNProbeSession: @unchecked Sendable {
	private let server: STUNServer
	private let timeoutSeconds: Double
	private let transactionID: [UInt8]
	private let queue = DispatchQueue(label: "ai.decart.connectivity.stun")

	private var connection: NWConnection?
	private var continuation: CheckedContinuation<ConnectivityMetrics, Never>?
	private var resumed = false
	private var reachedReady = false
	private var startInstant: DispatchTime?
	private var pendingResult: ConnectivityMetrics?
	private var timeoutItem: DispatchWorkItem?

	init(server: STUNServer, timeoutMs: Int) {
		self.server = server
		timeoutSeconds = Double(max(0, timeoutMs)) / 1000
		transactionID = STUNProbeSession.randomTransactionID()
	}

	func run() async -> ConnectivityMetrics {
		await withTaskCancellationHandler {
			await withCheckedContinuation { (cont: CheckedContinuation<ConnectivityMetrics, Never>) in
				queue.async { self.start(cont) }
			}
		} onCancel: {
			queue.async { self.finish(ConnectivityMetrics(transport: .failed, rttMs: nil)) }
		}
	}

	// MARK: - Queue-confined state machine (all methods below run on `queue`)

	private func start(_ cont: CheckedContinuation<ConnectivityMetrics, Never>) {
		// Cancellation may have finished us before start ran.
		if resumed {
			cont.resume(returning: pendingResult ?? ConnectivityMetrics(transport: .failed, rttMs: nil))
			return
		}
		continuation = cont

		guard let port = NWEndpoint.Port(rawValue: server.port) else {
			finish(ConnectivityMetrics(transport: .failed, rttMs: nil))
			return
		}
		let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(server.host), port: port)
		let conn = NWConnection(to: endpoint, using: .udp)
		connection = conn

		conn.stateUpdateHandler = { [self] state in handleState(state) }

		let item = DispatchWorkItem { [self] in handleTimeout() }
		timeoutItem = item
		queue.asyncAfter(deadline: .now() + timeoutSeconds, execute: item)

		conn.start(queue: queue)
	}

	private func handleState(_ state: NWConnection.State) {
		switch state {
		case .ready:
			reachedReady = true
			sendBindingRequest()
		case let .failed(error):
			DecartLogger.log("preflight: connection failed: \(error)", level: .warning)
			finish(ConnectivityMetrics(transport: .failed, rttMs: nil))
		default:
			// .waiting/.preparing: path not usable yet — let the timeout decide
			// (relay if we later reached .ready, otherwise failed).
			break
		}
	}

	private func sendBindingRequest() {
		guard let conn = connection else { return }
		startInstant = DispatchTime.now()
		let request = Data(STUNProbeSession.bindingRequest(transactionID: transactionID))
		conn.send(content: request, completion: .contentProcessed { [self] error in
			queue.async { [self] in
				if let error {
					DecartLogger.log("preflight: send failed: \(error)", level: .warning)
					finish(ConnectivityMetrics(transport: .failed, rttMs: nil))
					return
				}
				receiveResponse()
			}
		})
	}

	private func receiveResponse() {
		guard let conn = connection else { return }
		conn.receiveMessage { [self] data, _, _, error in
			queue.async { [self] in
				if error != nil {
					// Socket-level receive error: let the timeout classify (relay if ready).
					return
				}
				if let data, isValidStunResponse(data) {
					finish(ConnectivityMetrics(transport: .udp, rttMs: measuredRttMs()))
				} else if !resumed {
					// Stray/invalid datagram — keep waiting for a valid one until timeout.
					receiveResponse()
				}
			}
		}
	}

	private func handleTimeout() {
		finish(ConnectivityMetrics(transport: reachedReady ? .relay : .failed, rttMs: nil))
	}

	private func finish(_ metrics: ConnectivityMetrics) {
		guard !resumed else { return }
		resumed = true
		timeoutItem?.cancel()
		timeoutItem = nil
		connection?.cancel()
		connection = nil
		if let cont = continuation {
			continuation = nil
			cont.resume(returning: metrics)
		} else {
			pendingResult = metrics
		}
	}

	// MARK: - STUN helpers

	private func measuredRttMs() -> Int? {
		guard let start = startInstant else { return nil }
		let elapsedNanos = DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds
		return Int((Double(elapsedNanos) / 1_000_000).rounded())
	}

	private func isValidStunResponse(_ data: Data) -> Bool {
		guard data.count >= 20 else { return false }
		let bytes = [UInt8](data)
		// Binding Success Response (0x0101).
		guard bytes[0] == 0x01, bytes[1] == 0x01 else { return false }
		// Magic cookie 0x2112A442.
		guard bytes[4] == 0x21, bytes[5] == 0x12, bytes[6] == 0xA4, bytes[7] == 0x42 else { return false }
		// Transaction ID must match exactly (discard stray/spoofed datagrams).
		for i in 0..<12 where bytes[8 + i] != transactionID[i] { return false }
		return true
	}

	/// 20-byte STUN Binding Request header, no attributes.
	private static func bindingRequest(transactionID: [UInt8]) -> [UInt8] {
		var packet: [UInt8] = []
		packet += [0x00, 0x01] // Message Type: Binding Request
		packet += [0x00, 0x00] // Message Length: 0 (no attributes)
		packet += [0x21, 0x12, 0xA4, 0x42] // Magic Cookie
		packet += transactionID // 96-bit Transaction ID
		return packet
	}

	private static func randomTransactionID() -> [UInt8] {
		var bytes = [UInt8](repeating: 0, count: 12)
		if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
			for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
		}
		return bytes
	}
}
