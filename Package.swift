// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DecartSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "DecartSDK",
            targets: ["DecartSDK"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC.git", from: "120.0.0")
    ],
    targets: [
        .target(
            name: "DecartSDK",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
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
