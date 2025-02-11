// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AmplitudeCore",
    platforms: [
        .macOS("10.15"),
        .iOS("13.0"),
        .tvOS("13.0"),
        .watchOS("7.0"),
        .visionOS("1.0"),
    ],
    products: [
        .library(
            name: "AmplitudeCore",
            targets: ["AmplitudeCore"]),
    ],
    targets: [
        .target(name: "AmplitudeCore"),
        .testTarget(
            name: "AmplitudeCoreTests",
            dependencies: ["AmplitudeCore"])
    ]
)
