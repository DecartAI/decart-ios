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
