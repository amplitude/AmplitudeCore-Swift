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
//        .library(
//            name: "AmplitudeCoreNoUIKitFramework",
//            targets: ["AmplitudeCoreNoUIKitFramework"])
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
            url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.2.4/AmplitudeCore.zip",
            checksum: "8fe24d0808b1b75d9c17c92c6bd85785015b85d288478d5d79afe84fd0968f10"),
//        .binaryTarget(
//            name: "AmplitudeCoreNoUIKitFramework",
//            url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.2.4/AmplitudeCoreNoUIKit.zip",
//            checksum: ""),
        .testTarget(
            name: "AmplitudeCoreTests",
            dependencies: ["AmplitudeCore"])
    ]
)
