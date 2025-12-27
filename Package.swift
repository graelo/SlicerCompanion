// swift-tools-version: 6.0
// Package.swift for running tests via `swift test`
// This is used for CI and does not interfere with the Xcode project.

import PackageDescription

let package = Package(
    name: "SlicerCompanion",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SlicerCompanionLib",
            targets: ["SlicerCompanionLib"]
        )
    ],
    targets: [
        .target(
            name: "SlicerCompanionLib",
            dependencies: [],
            path: "Shared",
            sources: ["ThumbnailExtractor.swift"]
        ),
        .testTarget(
            name: "SlicerCompanionTests",
            dependencies: ["SlicerCompanionLib"],
            path: "SlicerCompanionTests",
            exclude: [],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
