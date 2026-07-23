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
            url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.4.9/AmplitudeCore.zip",
            checksum: "4e3ed6433d8721a0142f200648b83f671bfaabf96c28236245f2017a3cde4de7"),
       .binaryTarget(
           name: "AmplitudeCoreNoUIKitFramework",
           url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.4.9/AmplitudeCoreNoUIKit.zip",
           checksum: "8f486e862593cc3f8722eeadec75ebf70deab7e419258657de54061b692f9912"),
        .testTarget(
            name: "AmplitudeCoreTests",
            dependencies: ["AmplitudeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
