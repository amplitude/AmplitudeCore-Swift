//
//  AppEnvironmentTests.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 07/23/26.
//

import XCTest
@_spi(Internal) @testable import AmplitudeCore

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
final class AppEnvironmentTests: XCTestCase {

    override func tearDown() {
        AppEnvironment.overrideForTesting = nil
        super.tearDown()
    }

    func testTestOverrideTakesPrecedence() {
        AppEnvironment.overrideForTesting = .testFlight
        XCTAssertEqual(AppEnvironment.current, .testFlight)

        AppEnvironment.overrideForTesting = nil
        // Test hosts never run as App Store installs.
        XCTAssertNotEqual(AppEnvironment.current, .appStore)
    }

    func testContainingAppBundleURLResolvesExtensionHost() {
        // iOS layout
        XCTAssertEqual(
            AppEnvironment.containingAppBundleURL(
                of: URL(fileURLWithPath: "/private/var/containers/Bundle/Application/ABC/MyApp.app/PlugIns/Widget.appex"))?.path,
            "/private/var/containers/Bundle/Application/ABC/MyApp.app")
        // macOS layout
        XCTAssertEqual(
            AppEnvironment.containingAppBundleURL(
                of: URL(fileURLWithPath: "/Applications/MyApp.app/Contents/PlugIns/Share.appex"))?.path,
            "/Applications/MyApp.app")
    }

    func testContainingAppBundleURLReturnsNilForNonExtensions() {
        // Not an extension bundle.
        XCTAssertNil(AppEnvironment.containingAppBundleURL(
            of: URL(fileURLWithPath: "/Applications/MyApp.app")))
        // Extension with no enclosing .app ancestor.
        XCTAssertNil(AppEnvironment.containingAppBundleURL(
            of: URL(fileURLWithPath: "/tmp/Orphan.appex")))
    }

    func testEnvironmentTagValues() {
        XCTAssertEqual(AppEnvironment.appStore.rawValue, "appstore")
        XCTAssertEqual(AppEnvironment.testFlight.rawValue, "testflight")
        XCTAssertEqual(AppEnvironment.developerID.rawValue, "developerid")
        XCTAssertEqual(AppEnvironment.development.rawValue, "development")
        XCTAssertEqual(AppEnvironment.simulator.rawValue, "simulator")
    }

    func testEnvironmentTagIsSetOnDiagnostics() async {
        AppEnvironment.overrideForTesting = .testFlight
        let client = DiagnosticsClient(
            apiKey: "test-app-environment-key",
            instanceName: "test-app-environment-\(UUID().uuidString)",
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil
        )
        let tag = await client.getTag(name: "app.environment")
        XCTAssertEqual(tag, "testflight")
        await client.stopFlushTimer()
    }

    func testEnvironmentTagDoesNotAffectSampling() async {
        AppEnvironment.overrideForTesting = .simulator
        let client = DiagnosticsClient(
            apiKey: "test-app-environment-key",
            instanceName: "test-app-environment-\(UUID().uuidString)",
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil
        )
        let shouldTrack = await client.shouldTrack
        XCTAssertTrue(shouldTrack, "Tag-only phase: environment must not gate sampling")
        await client.stopFlushTimer()
    }
}
