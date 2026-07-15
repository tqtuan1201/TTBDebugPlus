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
        // This package exposes pure engines for unit tests (`swift test`).
        .library(
            name: "JSONTools",
            targets: ["JSONTools"]
        ),
        .library(
            name: "LocalhostTools",
            targets: ["LocalhostTools"]
        ),
        .library(
            name: "ColorPickerTools",
            targets: ["ColorPickerTools"]
        ),
        .library(
            name: "DesignSystemTools",
            targets: ["DesignSystemTools"]
        )
    ],
    targets: [
        .target(
            name: "JSONTools",
            path: "TTBDebugPlus/Services/JSON"
        ),
        .target(
            name: "LocalhostTools",
            path: "TTBDebugPlus",
            sources: [
                "Models/Localhost/LocalhostModels.swift",
                "Services/DevTools/Engines/Localhost/LocalhostPortScanner.swift",
                "Services/DevTools/Engines/Localhost/LocalhostProcessClassifier.swift",
                "Services/DevTools/Engines/Localhost/LocalhostProcessController.swift",
                "Services/DevTools/Engines/Localhost/LocalhostServerLauncher.swift"
            ]
        ),
        .target(
            name: "ColorPickerTools",
            path: "TTBDebugPlus",
            sources: [
                "Models/DevTools/ColorPickerModels.swift",
                "Services/DevTools/Engines/ColorPicker/ColorFormatEngine.swift",
                "Services/DevTools/Engines/ColorPicker/WCAGContrastEngine.swift",
                "Services/DevTools/Engines/ColorPicker/DesignTokenMatcher.swift"
            ]
        ),
        .testTarget(
            name: "JSONToolsTests",
            dependencies: ["JSONTools"],
            path: "Tests/JSONToolsTests"
        ),
        .testTarget(
            name: "LocalhostToolsTests",
            dependencies: ["LocalhostTools"],
            path: "Tests/LocalhostToolsTests"
        ),
        .testTarget(
            name: "ColorPickerToolsTests",
            dependencies: ["ColorPickerTools"],
            path: "Tests/ColorPickerToolsTests"
        ),
        .target(
            name: "DesignSystemTools",
            path: "TTBDebugPlus/DesignSystem",
            sources: [
                "DesignSystemMetrics.swift"
            ]
        ),
        .testTarget(
            name: "DesignSystemToolsTests",
            dependencies: ["DesignSystemTools"],
            path: "Tests/DesignSystemToolsTests"
        )
    ]
)
