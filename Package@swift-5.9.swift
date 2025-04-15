// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "AmplitudeCore",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v11),
        .tvOS(.v11),
        .watchOS(.v4),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "AmplitudeCore",
            targets: ["AmplitudeCore"]),
        .library(
            name: "AmplitudeCoreFramework",
            targets: ["AmplitudeCoreFramework"])
    ],
    targets: [
        .target(
            name: "AmplitudeCore",
            resources: [.process("PrivacyInfo.xcprivacy")]),
        .binaryTarget(
            name: "AmplitudeCoreFramework",
            url: "https://github.com/amplitude/AmplitudeCore-Swift/releases/download/v1.0.4/AmplitudeCore.zip",
            checksum: "0e23da3d73fdb79362e9130d79e29736ee08252e6290cf726ac556f2bac15472"),
        .testTarget(
            name: "AmplitudeCoreTests",
            dependencies: ["AmplitudeCore"])
    ]
)
