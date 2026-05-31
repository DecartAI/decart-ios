import Foundation
import Network

struct NetworkPathSnapshot: Sendable, Equatable {
	let status: String
	let interfaces: [String]
	let isExpensive: Bool
	let isConstrained: Bool
}

final class NetworkPathObserver: @unchecked Sendable {
	private let monitor: NWPathMonitor
	private let queue: DispatchQueue
	private var lastSnapshot: NetworkPathSnapshot?
	private let onChange: @Sendable (NetworkPathSnapshot, NetworkPathSnapshot?) -> Void

	init(onChange: @escaping @Sendable (NetworkPathSnapshot, NetworkPathSnapshot?) -> Void) {
		self.monitor = NWPathMonitor()
		self.queue = DispatchQueue(label: "ai.decart.realtime.network-path")
		self.onChange = onChange
	}

	func start() {
		monitor.pathUpdateHandler = { [weak self] path in
			guard let self else { return }
			let snapshot = NetworkPathSnapshot(from: path)
			let previous = self.lastSnapshot
			guard snapshot != previous else { return }
			self.lastSnapshot = snapshot
			self.onChange(snapshot, previous)
		}
		monitor.start(queue: queue)
	}

	func stop() {
		monitor.cancel()
		lastSnapshot = nil
	}

	/// Enumerates the device's local IP addresses per interface name
	/// (e.g. `en0` for Wi-Fi, `pdp_ip0` for cellular). Loopback is skipped and
	/// IPv6 scope identifiers are stripped. Useful for correlating with the
	/// host ICE candidates that WebRTC gathers.
	static func interfaceAddresses() -> [String: [String]] {
		var result: [String: [String]] = [:]
		var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
		guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else {
			return result
		}
		defer { freeifaddrs(ifaddrPointer) }

		for pointer in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
			let interface = pointer.pointee
			guard let addr = interface.ifa_addr else { continue }
			let family = addr.pointee.sa_family
			guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

			let name = String(cString: interface.ifa_name)
			guard name != "lo0" else { continue }

			var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
			let result0 = getnameinfo(
				addr,
				socklen_t(addr.pointee.sa_len),
				&host,
				socklen_t(host.count),
				nil,
				0,
				NI_NUMERICHOST
			)
			guard result0 == 0 else { continue }

			let rawAddress = String(cString: host)
			let address = rawAddress.split(separator: "%").first.map(String.init) ?? rawAddress
			result[name, default: []].append(address)
		}

		return result
	}
}

private extension NetworkPathSnapshot {
	init(from path: NWPath) {
		let status: String
		switch path.status {
		case .satisfied: status = "satisfied"
		case .unsatisfied: status = "unsatisfied"
		case .requiresConnection: status = "requiresConnection"
		@unknown default: status = "unknown"
		}

		var interfaces: [String] = []
		if path.usesInterfaceType(.wifi) { interfaces.append("wifi") }
		if path.usesInterfaceType(.cellular) { interfaces.append("cellular") }
		if path.usesInterfaceType(.wiredEthernet) { interfaces.append("wiredEthernet") }
		if path.usesInterfaceType(.loopback) { interfaces.append("loopback") }
		if path.usesInterfaceType(.other) { interfaces.append("other") }

		self.init(
			status: status,
			interfaces: interfaces,
			isExpensive: path.isExpensive,
			isConstrained: path.isConstrained
		)
	}
}
