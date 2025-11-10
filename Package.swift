// swift-tools-version: 6.0.3
import PackageDescription

let package = Package(
	name: "DecartSDK",
	platforms: [
		.iOS(.v17),
		.macOS(.v12),
	],
	products: [
		.library(
			name: "DecartSDK",
			targets: ["DecartSDK"]
		)
	],
	dependencies: [
		.package(url: "https://github.com/stasel/WebRTC.git", from: "140.0.0")
	],
	targets: [
		.target(
			name: "DecartSDK",
			dependencies: [
				.product(name: "WebRTC", package: "WebRTC")
			],
			path: "Sources/DecartSDK"
		)
	]
)
