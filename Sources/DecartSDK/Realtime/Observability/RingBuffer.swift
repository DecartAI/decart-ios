import Foundation

/// Fixed-capacity rolling window of `Double` samples. Value type. `nil` pushes
/// are ignored (a missing metric does not displace a real one). Windows are tiny
/// (≤ a handful), so `median()` sorts a copy.
struct RingBuffer {
	private var values: [Double] = []
	private let capacity: Int

	init(capacity: Int) {
		self.capacity = max(1, capacity)
	}

	mutating func push(_ value: Double?) {
		guard let value else { return }
		values.append(value)
		if values.count > capacity { values.removeFirst() }
	}

	func median() -> Double? {
		guard !values.isEmpty else { return nil }
		let sorted = values.sorted()
		let mid = sorted.count / 2
		return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
	}

	func min() -> Double? {
		values.min()
	}

	mutating func clear() {
		values.removeAll()
	}
}
