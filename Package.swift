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
            url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.3.0/AmplitudeCore.zip",
            checksum: "18a42d9c61d9d9cd44cc5ce5ad308dc0353fbfc4a48441db86055c74c3a7a119"),
//        .binaryTarget(
//            name: "AmplitudeCoreNoUIKitFramework",
//            url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.3.0/AmplitudeCoreNoUIKit.zip",
//            checksum: "d33d24049bc1ad4c3dfbdb2e6c61e40daa5593600cb99eea3e77691119ea7534"),
        .testTarget(
            name: "AmplitudeCoreTests",
            dependencies: ["AmplitudeCore"])
    ]
)
