// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "AmplitudeCore",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v11),
        .tvOS(.v11),
        .watchOS(.v4),
    ],
    products: [
        .library(
            name: "AmplitudeCore",
            targets: ["AmplitudeCore"]),
        .library(
            name: "AmplitudeCoreNoUIKit",
            targets: ["AmplitudeCoreNoUIKit"]),
        .library(
            name: "AmplitudeCoreFramework",
            targets: ["AmplitudeCoreFramework"]),
       .library(
           name: "AmplitudeCoreNoUIKitFramework",
           targets: ["AmplitudeCoreNoUIKitFramework"])
    ],
    targets: [
        .target(
            name: "AmplitudeCore",
            resources: [.process("PrivacyInfo.xcprivacy")]),
        .target(
            name: "AmplitudeCoreNoUIKit",
            resources: [.process("PrivacyInfo.xcprivacy")],
            swiftSettings: [.define("AMPLITUDE_DISABLE_UIKIT")]),
        .binaryTarget(
            name: "AmplitudeCoreFramework",
            url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.5.3/AmplitudeCore.zip",
            checksum: "3561f7f78752a4880914416f91de59339e4e9f508377f5ac6102fc1b77bfd2aa"),
       .binaryTarget(
           name: "AmplitudeCoreNoUIKitFramework",
           url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.5.3/AmplitudeCoreNoUIKit.zip",
           checksum: "8f9d45363bc08157a4ce4664c500e6ae4645db9ecb4a6f117f06879d78b9cd3f"),
        .testTarget(
            name: "AmplitudeCoreTests",
            dependencies: ["AmplitudeCore"])
    ]
)
