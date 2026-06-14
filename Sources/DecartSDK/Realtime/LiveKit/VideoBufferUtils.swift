import CoreImage
import CoreVideo

/// Create a `CVPixelBufferPool` for the given size/format, or nil on failure.
func makePixelBufferPool(width: Int, height: Int, pixelFormat: OSType) -> CVPixelBufferPool? {
	let attrs: [CFString: Any] = [
		kCVPixelBufferPixelFormatTypeKey: pixelFormat,
		kCVPixelBufferWidthKey: width,
		kCVPixelBufferHeightKey: height,
		kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
	]
	var pool: CVPixelBufferPool?
	guard CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool) == kCVReturnSuccess else { return nil }
	return pool
}

extension CVPixelBuffer {
	/// Lock the buffer and run `body` with the luma (Y / plane 0) byte pointer and
	/// its dimensions. Returns nil (without calling `body`) if there is no plane 0.
	@discardableResult
	func withLumaPlane<T>(
		readOnly: Bool = false,
		_ body: (_ base: UnsafeMutablePointer<UInt8>, _ width: Int, _ height: Int, _ bytesPerRow: Int) -> T
	) -> T? {
		guard CVPixelBufferGetPlaneCount(self) >= 1 else { return nil }
		let flags: CVPixelBufferLockFlags = readOnly ? .readOnly : []
		CVPixelBufferLockBaseAddress(self, flags)
		defer { CVPixelBufferUnlockBaseAddress(self, flags) }
		guard let base = CVPixelBufferGetBaseAddressOfPlane(self, 0) else { return nil }
		return body(
			base.assumingMemoryBound(to: UInt8.self),
			CVPixelBufferGetWidthOfPlane(self, 0),
			CVPixelBufferGetHeightOfPlane(self, 0),
			CVPixelBufferGetBytesPerRowOfPlane(self, 0)
		)
	}
}

/// Center-crop to the target aspect and scale to `targetWidth`×`targetHeight`
/// (matching LiveKit's `cropAndScaleFromCenter`); returns `image` unchanged if
/// already sized.
func centerCropAndScale(_ image: CIImage, toWidth targetWidth: Int, height targetHeight: Int) -> CIImage {
	let extent = image.extent
	guard extent.width > 0, extent.height > 0,
		Int(extent.width) != targetWidth || Int(extent.height) != targetHeight else {
		return image
	}

	let target = CGFloat(targetWidth) / CGFloat(targetHeight)
	let source = extent.width / extent.height

	var cropWidth = extent.width
	var cropHeight = extent.height
	if source > target {
		cropWidth = extent.height * target
	} else {
		cropHeight = extent.width / target
	}
	let cropX = extent.origin.x + (extent.width - cropWidth) / 2
	let cropY = extent.origin.y + (extent.height - cropHeight) / 2

	return image
		.cropped(to: CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight))
		.transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))
		.transformed(by: CGAffineTransform(scaleX: CGFloat(targetWidth) / cropWidth, y: CGFloat(targetHeight) / cropHeight))
}
