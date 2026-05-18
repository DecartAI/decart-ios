// swift-tools-version: 6.2.1
import PackageDescription

let package = Package(
	name: "DecartSDK",
	platforms: [
		.iOS(.v17),
		.macOS(.v12)
	],
	products: [
		.library(
			name: "DecartSDK",
			targets: ["DecartSDK"]
		)
	],
	dependencies: [
		.package(url: "https://github.com/livekit/client-sdk-swift.git", from: "2.5.0"),
		.package(
			url: "https://github.com/shareup/websocket-apple.git",
			from: "4.1.0"
		)
	],
	targets: [
		.target(
			name: "DecartSDK",
			dependencies: [
				.product(name: "LiveKit", package: "client-sdk-swift"),
				.product(name: "WebSocket", package: "websocket-apple")
			],
			path: "Sources/DecartSDK"
		),
		.testTarget(
			name: "DecartSDKTests",
			dependencies: ["DecartSDK"],
			path: "Tests/DecartSDKTests"
		)
	]
)
