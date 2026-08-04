// swift-tools-version:6.4

import PackageDescription

let package = Package(
    name: "AmplitudeCore",
    platforms: [
        .macOS(.v12),
        .iOS(.v12),
        .tvOS(.v15),
        .watchOS(.v9),
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
            url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.4.10/AmplitudeCore.zip",
            checksum: "4aa5bd6f885e22ced4cacc5be4c87feaec8b9ae06c565c4336cdfd1b70d761aa"),
       .binaryTarget(
           name: "AmplitudeCoreNoUIKitFramework",
           url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.4.10/AmplitudeCoreNoUIKit.zip",
           checksum: "04ea6a58254dcf58f23ccf235ef35143d2ea5ba4b53a34bcf3deb8f04a54109a"),
        .testTarget(
            name: "AmplitudeCoreTests",
            dependencies: ["AmplitudeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
