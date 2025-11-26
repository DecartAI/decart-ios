//
//  UIImage+Normalized.swift
//  Example
//
//  Created by Alon Bar-el on 23/11/2025.
//

import UIKit

extension UIImage {
	func fixOrientation() -> UIImage? {
		if imageOrientation == .up {
			return self
		}

		UIGraphicsBeginImageContext(size)
		draw(in: CGRect(origin: .zero, size: size))
		let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
		UIGraphicsEndImageContext()
		return normalizedImage
	}
}
