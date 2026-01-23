// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "AmplitudeCore",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v12),
        .tvOS(.v12),
        .watchOS(.v4),
        .visionOS(.v1),
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
            resources: [.process("PrivacyInfo.xcprivacy")],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "AmplitudeCoreNoUIKit",
            resources: [.process("PrivacyInfo.xcprivacy")],
            swiftSettings: [.swiftLanguageMode(.v5), .define("AMPLITUDE_DISABLE_UIKIT")]),
        .binaryTarget(
            name: "AmplitudeCoreFramework",
            url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.3.4/AmplitudeCore.zip",
            checksum: "bf76fd366ea32eb04e4186a2ba313bdb7b3da3782caf543ae77a63e79b203da4"),
       .binaryTarget(
           name: "AmplitudeCoreNoUIKitFramework",
           url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.3.4/AmplitudeCoreNoUIKit.zip",
           checksum: "94a0e621f7191398aee1a783b45d63a363f8023abe0e7053c9393d9268159072"),
        .testTarget(
            name: "AmplitudeCoreTests",
            dependencies: ["AmplitudeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
