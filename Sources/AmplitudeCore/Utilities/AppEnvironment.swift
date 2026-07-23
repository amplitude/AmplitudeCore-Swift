//
//  AppEnvironment.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 07/23/26.
//

import Foundation
#if os(macOS) || targetEnvironment(macCatalyst)
import Security
#endif

/// Distribution channel of the host app.
///
/// Diagnostics tags every session with this value: simulator, development, and
/// TestFlight runs routinely exercise stress scenarios and debug tooling whose
/// outliers dominate max-type aggregates and skew guard-threshold calibration,
/// so aggregates need to be filterable to production traffic. Production
/// channels are `appStore` and (on macOS) `developerID`. Once the tag proves
/// reliable in the field, sampling will be gated on them (SDKI-14).
enum AppEnvironment: String, Sendable {
    case appStore = "appstore"
    case testFlight = "testflight"
    /// Direct distribution signed with a Developer ID certificate (macOS only) —
    /// production end-user traffic, just not store-verified.
    case developerID = "developerid"
    case development = "development"
    case simulator = "simulator"

    /// Test hook: when set, `current` returns this value instead of the detected one.
    nonisolated(unsafe) static var overrideForTesting: AppEnvironment?

    static var current: AppEnvironment {
        overrideForTesting ?? detected
    }

    /// Test hook: when set, `isReleaseBuild` returns this value instead of the detected one.
    nonisolated(unsafe) static var releaseBuildOverrideForTesting: Bool?

    /// Whether the host app is a release (non-debuggable) build.
    ///
    /// Unlike the distribution channel above — which relies on best-effort store
    /// heuristics — this is deterministic: debuggable builds are marked by the
    /// get-task-allow entitlement (macOS) or a development provisioning profile
    /// carrying it (iOS family), and source-integrated SDK builds compile with
    /// the host app's configuration. Guard-phase sampling (SDKI-14) will trust
    /// all release builds.
    static var isReleaseBuild: Bool {
        releaseBuildOverrideForTesting ?? detectedReleaseBuild
    }

    private static let detectedReleaseBuild: Bool = {
#if DEBUG
        // Source integration (SPM/CocoaPods) compiles the SDK with the host
        // app's build configuration; a debug host means a debug SDK.
        return false
#elseif targetEnvironment(simulator)
        return false
#elseif os(macOS) || targetEnvironment(macCatalyst)
        return !isDebuggableBuild
#else
        // Development installs embed a provisioning profile whose entitlements
        // carry get-task-allow=true (required for attaching a debugger). Store
        // installs embed no profile; ad-hoc/enterprise profiles carry false.
        guard let entitlements = embeddedProvisioningEntitlements() else {
            return true
        }
        return (entitlements["get-task-allow"] as? Bool) != true
#endif
    }()

    private static let detected: AppEnvironment = {
#if targetEnvironment(simulator)
        return .simulator
#elseif os(macOS) || targetEnvironment(macCatalyst)
        // Debuggable (Xcode-run / development-exported) builds carry the
        // get-task-allow entitlement regardless of signing identity.
        if isDebuggableBuild {
            return .development
        }
        // Store installs carry a receipt file (the host app's, for extensions).
        // Mac receipts keep the production filename even for TestFlight, but the
        // receipt payload embeds the environment as a plain string.
        if let receiptURL = mainAppBundle.appStoreReceiptURL,
           let receipt = try? Data(contentsOf: receiptURL) {
            return receipt.range(of: Data("ProductionSandbox".utf8)) != nil ? .testFlight : .appStore
        }
        // Direct distribution signed with a Developer ID certificate is
        // production traffic; everything else stays conservative.
        return isDeveloperIDSigned ? .developerID : .development
#else
        // Development / ad-hoc / enterprise builds embed a provisioning profile;
        // App Store and TestFlight installs do not. Extensions check the
        // containing app's bundle.
        if mainAppBundle.path(forResource: "embedded", ofType: "mobileprovision") != nil {
            return .development
        }
        // TestFlight (and other sandbox) installs use a sandbox receipt — same
        // technique as Firebase's GULAppEnvironmentUtil. Check both the current
        // process's bundle (receipt name derived from the install environment)
        // and the resolved host app bundle (bundle-relative receipt path), since
        // in app extensions either one may carry the sandbox naming.
        if [Bundle.main, mainAppBundle].contains(where: { $0.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" }) {
            return .testFlight
        }
        return .appStore
#endif
    }()

#if os(macOS) || targetEnvironment(macCatalyst)
    /// Whether the current process carries the `get-task-allow` entitlement —
    /// true for Xcode-run and development-exported builds, false for App Store,
    /// TestFlight, and Developer ID distribution.
    private static var isDebuggableBuild: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "get-task-allow" as CFString, nil) else {
            return false
        }
        return (value as? NSNumber)?.boolValue == true
    }

    /// Whether the current process's code signature chains to a
    /// "Developer ID Application" leaf certificate (direct distribution).
    private static var isDeveloperIDSigned: Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var infoCF: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
              let info = infoCF as? [String: Any],
              let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first,
              let summary = SecCertificateCopySubjectSummary(leaf) as String? else {
            return false
        }
        return summary.hasPrefix("Developer ID Application")
    }
#endif

    /// Entitlements embedded in the host app's provisioning profile, or nil
    /// when no profile is embedded (store installs).
    private static func embeddedProvisioningEntitlements() -> [String: Any]? {
        guard let path = mainAppBundle.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return provisioningEntitlements(in: data)
    }

    /// Extracts the `Entitlements` dictionary from a provisioning profile blob —
    /// a CMS envelope wrapping an XML plist.
    static func provisioningEntitlements(in data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else {
            return nil
        }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return plist["Entitlements"] as? [String: Any]
    }

    /// `Bundle.main`, except inside an app extension (`.appex`), where receipts
    /// and provisioning profiles live in the containing app's bundle instead.
    /// Falls back to `Bundle.main` when the containing app cannot be resolved.
    private static var mainAppBundle: Bundle {
        let main = Bundle.main
        guard let hostURL = containingAppBundleURL(of: main.bundleURL),
              let host = Bundle(url: hostURL) else {
            return main
        }
        return host
    }

    /// Resolves the containing `.app` bundle URL for an app-extension bundle URL.
    /// Returns nil when the URL is not an extension or no enclosing app exists.
    static func containingAppBundleURL(of bundleURL: URL) -> URL? {
        guard bundleURL.pathExtension == "appex" else { return nil }
        var url = bundleURL.deletingLastPathComponent()
        while !url.path.isEmpty && url.path != "/" {
            if url.pathExtension == "app" {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        return nil
    }
}
