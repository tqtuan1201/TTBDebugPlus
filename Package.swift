// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TTBDebugPlus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // App is built via TTBDebugPlus.xcodeproj.
        // This package exposes pure JSON tools for unit tests (`swift test`).
        .library(
            name: "JSONTools",
            targets: ["JSONTools"]
        )
    ],
    targets: [
        .target(
            name: "JSONTools",
            path: "TTBDebugPlus/Services/JSON"
        ),
        .testTarget(
            name: "JSONToolsTests",
            dependencies: ["JSONTools"],
            path: "Tests/JSONToolsTests"
        )
    ]
)
