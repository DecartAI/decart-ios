import Foundation

/// RGBA, row-major pixel buffer — the structural shape the marker codec operates
/// on (the analog of a canvas `ImageData`). `data` length must be width*height*4.
struct PixelMarkerImage {
	let width: Int
	let height: Int
	var data: [UInt8]

	init(width: Int, height: Int, data: [UInt8]) {
		self.width = width
		self.height = height
		self.data = data
	}
}

/// Port of the server's E2E pixel-latency marker protocol
/// (`inference_server/rt/bench/pixel_marker.py`) — used to measure true
/// glass-to-glass latency. The client stamps a monotonic 16-bit sequence number
/// into the bottom-left of every outgoing frame; the server (with `pixel_latency`
/// on) re-stamps it onto the matching output; the client reads it back off the
/// rendered frame.
///
/// Works on luma: grayscale blocks (R=G=B=v) land Y≈v after RGB→YUV; reads compute
/// luma and threshold at 128. SYNC pattern + per-row checksum + 4 redundant rows +
/// block-size auto-detect survive VP8/VP9 quantization and transport scaling.
/// Intentionally byte-compatible with the server — keep constants and bit layout in sync.
enum PixelMarker {
	static let sync = [200, 50, 200, 50]
	static let syncLen = 4
	static let dataBits = 16
	static let checksumBits = 4
	/// 4 sync + 16 data + 4 checksum logical columns.
	static let totalLogical = 24
	/// Redundant logical rows, majority-voted on read.
	static let markerRows = 4
	/// Physical pixels per logical pixel when stamping (native resolution).
	static let blockSize = 8

	/// Candidate received block sizes, ordered by likelihood (nominal 8, no scaling).
	static let candidateBlockSizes = [8, 4, 6, 2, 12, 10, 16, 5, 7, 14, 3]

	/// Smallest frame that can hold the marker at nominal block size.
	static let minMarkerWidth = totalLogical * blockSize // 192
	static let minMarkerHeight = markerRows * blockSize // 32
	/// Tallest the marker can be in a received frame (largest auto-detect block size).
	static let maxMarkerHeight = markerRows * 16 // 64

	/// BT.601 luma approximation (integer, matches a >=128 threshold either way).
	static func luma(_ r: Int, _ g: Int, _ b: Int) -> Int {
		(77 * r + 150 * g + 29 * b) >> 8
	}

	static func isHigh(_ v: Int) -> Bool { v >= 128 }

	/// XOR of the four 4-bit nibbles of the 16-bit seq (matches the server).
	static func checksumNibbles(_ seq: Int) -> Int {
		var checksum = 0
		var i = 0
		while i < dataBits {
			checksum ^= (seq >> i) & 0xf
			i += 4
		}
		return checksum
	}

	/// The `totalLogical` grayscale values for one logical row encoding `seq`.
	static func rowValues(_ seq: Int) -> [Int] {
		let masked = seq & 0xffff
		var values = sync
		for i in 0..<dataBits {
			values.append((masked >> (dataBits - 1 - i)) & 1 == 1 ? 200 : 50)
		}
		let checksum = checksumNibbles(masked)
		for i in 0..<checksumBits {
			values.append((checksum >> (checksumBits - 1 - i)) & 1 == 1 ? 200 : 50)
		}
		return values // length == totalLogical
	}

	/// Stamp `seq` into the bottom-left of a luma plane via `set(x, y, value)`.
	/// Returns false (no-op) if the frame is too small. Always stamps at
	/// blockSize=8, matching the server's native-resolution stamp. Pure: the same
	/// code serves unit tests (in-memory RGBA) and live frames (I420/NV12 Y plane).
	@discardableResult
	static func stamp(width: Int, height: Int, seq: Int, set: (_ x: Int, _ y: Int, _ value: Int) -> Void) -> Bool {
		guard width >= minMarkerWidth, height >= minMarkerHeight else { return false }
		let values = rowValues(seq)
		for logRow in 0..<markerRows {
			let rowStart = height - (markerRows - logRow) * blockSize
			for by in 0..<blockSize {
				let y = rowStart + by
				if y < 0 || y >= height { continue }
				for logCol in 0..<totalLogical {
					let v = values[logCol]
					let xStart = logCol * blockSize
					let xEnd = min(xStart + blockSize, width)
					var x = xStart
					while x < xEnd {
						set(x, y, v)
						x += 1
					}
				}
			}
		}
		return true
	}

	/// RGBA convenience: stamp grayscale blocks (R=G=B=v) into `img` in place.
	@discardableResult
	static func stamp(_ img: inout PixelMarkerImage, seq: Int) -> Bool {
		let width = img.width
		return img.data.withUnsafeMutableBufferPointer { data in
			stamp(width: width, height: img.height, seq: seq) { x, y, value in
				let o = (y * width + x) * 4
				let v = UInt8(value)
				data[o] = v
				data[o + 1] = v
				data[o + 2] = v
				data[o + 3] = 255
			}
		}
	}

	private static func syncMatches(_ rv: [Int]) -> Bool {
		for i in 0..<syncLen where isHigh(sync[i]) != isHigh(rv[i]) { return false }
		return true
	}

	/// Read the marker seq from the bottom of a luma plane via `get(x, y)` (0...255),
	/// or nil if absent/unreadable. Auto-detects the received block size so it works
	/// at any received resolution (the transport may uniformly scale the frame).
	static func read(width: Int, height: Int, get: (_ x: Int, _ y: Int) -> Int) -> Int? {
		for blockSize in candidateBlockSizes {
			if width < totalLogical * blockSize || height < markerRows * blockSize { continue }
			if let seq = decodeAtBlockSize(width: width, height: height, blockSize: blockSize, get: get) {
				return seq
			}
		}
		return nil
	}

	/// RGBA convenience: read the marker from `img` (samples luma from R/G/B).
	static func read(_ img: PixelMarkerImage) -> Int? {
		let width = img.width
		return read(width: width, height: img.height) { x, y in
			let o = (y * width + x) * 4
			return luma(Int(img.data[o]), Int(img.data[o + 1]), Int(img.data[o + 2]))
		}
	}

	private static func decodeAtBlockSize(
		width: Int,
		height: Int,
		blockSize: Int,
		get: (_ x: Int, _ y: Int) -> Int
	) -> Int? {
		let half = blockSize >> 1
		var validRows: [[Int]] = []

		for logRow in 0..<markerRows {
			var row = height - (markerRows - logRow) * blockSize + half
			row = max(0, min(row, height - 1))
			var rv: [Int] = []
			for logCol in 0..<totalLogical {
				var col = logCol * blockSize + half
				col = max(0, min(col, width - 1))
				rv.append(get(col, row))
			}
			if syncMatches(rv) { validRows.append(rv) }
		}

		if validRows.isEmpty { return nil }
		let threshold = Double(validRows.count) / 2

		var seq = 0
		for i in 0..<dataBits {
			var votes = 0
			for rv in validRows where isHigh(rv[syncLen + i]) { votes += 1 }
			if Double(votes) > threshold { seq |= 1 << (dataBits - 1 - i) }
		}

		let expectedChecksum = checksumNibbles(seq)
		var actualChecksum = 0
		for i in 0..<checksumBits {
			var votes = 0
			for rv in validRows where isHigh(rv[syncLen + dataBits + i]) { votes += 1 }
			if Double(votes) > threshold { actualChecksum |= 1 << (checksumBits - 1 - i) }
		}

		return expectedChecksum == actualChecksum ? seq : nil
	}
}
