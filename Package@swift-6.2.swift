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
            url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.4.6/AmplitudeCore.zip",
            checksum: "dce493ef2bbb600b33f9a2fe0003c157376610872bf3939463254e9ebd41f833"),
       .binaryTarget(
           name: "AmplitudeCoreNoUIKitFramework",
           url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.4.6/AmplitudeCoreNoUIKit.zip",
           checksum: "d7f774cbd5a79482201b3b9ecb4cbd6c4aa1a0d8c61b90422dd9079a83593e99"),
        .testTarget(
            name: "AmplitudeCoreTests",
            dependencies: ["AmplitudeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
