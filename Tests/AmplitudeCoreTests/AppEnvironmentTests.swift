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
        AppEnvironment.releaseBuildOverrideForTesting = nil
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
        AppEnvironment.releaseBuildOverrideForTesting = true
        let client = DiagnosticsClient(
            apiKey: "test-app-environment-key",
            instanceName: "test-app-environment-\(UUID().uuidString)",
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil
        )
        let environmentTag = await client.getTag(name: "app.environment")
        XCTAssertEqual(environmentTag, "testflight")
        let releaseTag = await client.getTag(name: "app.release")
        XCTAssertEqual(releaseTag, "true")
        await client.stopFlushTimer()
    }

    func testDetectedReleaseBuildIsFalseOnTestHosts() {
        // Test hosts are debug builds (and often simulators).
        XCTAssertFalse(AppEnvironment.isReleaseBuild)
    }

    func testProvisioningEntitlementsParsing() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Name</key>
            <string>Dev Profile</string>
            <key>Entitlements</key>
            <dict>
                <key>get-task-allow</key>
                <true/>
            </dict>
        </dict>
        </plist>
        """
        // Emulate the CMS envelope: binary garbage around the XML plist.
        var blob = Data([0x30, 0x82, 0xDE, 0xAD])
        blob.append(Data(plist.utf8))
        blob.append(Data([0xBE, 0xEF]))

        let entitlements = AppEnvironment.provisioningEntitlements(in: blob)
        XCTAssertEqual(entitlements?["get-task-allow"] as? Bool, true)

        XCTAssertNil(AppEnvironment.provisioningEntitlements(in: Data([0x00, 0x01])))
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
