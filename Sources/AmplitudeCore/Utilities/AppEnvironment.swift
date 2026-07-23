//
//  AppEnvironment.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 07/23/26.
//

import Foundation

/// Distribution channel of the host app.
///
/// Diagnostics tags every session with this value: simulator, development, and
/// TestFlight runs routinely exercise stress scenarios and debug tooling whose
/// outliers dominate max-type aggregates and skew guard-threshold calibration,
/// so aggregates need to be filterable to production traffic. Once the tag
/// proves reliable in the field, sampling will be gated on `.appStore` (SDKI-14).
enum AppEnvironment: String, Sendable {
    case appStore = "appstore"
    case testFlight = "testflight"
    case development = "development"
    case simulator = "simulator"

    /// Test hook: when set, `current` returns this value instead of the detected one.
    nonisolated(unsafe) static var overrideForTesting: AppEnvironment?

    static var current: AppEnvironment {
        overrideForTesting ?? detected
    }

    private static let detected: AppEnvironment = {
#if targetEnvironment(simulator)
        return .simulator
#else
        // Extensions check the containing app's bundle.
        let bundle = mainAppBundle
        if hasEmbeddedProvisioningProfile(bundle) {
            return .development
        }
        // TestFlight (and other sandbox) installs use a sandbox receipt — same
        // technique as Firebase's GULAppEnvironmentUtil. Check both the current
        // process's bundle (receipt name derived from the install environment)
        // and the resolved host app bundle (bundle-relative receipt path), since
        // in app extensions either one may carry the sandbox naming.
        if [Bundle.main, bundle].contains(where: { $0.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" }) {
            return .testFlight
        }
#if os(macOS) || targetEnvironment(macCatalyst)
        // Dev-run Mac apps carry neither a provisioning profile nor a receipt,
        // so additionally require a real store receipt (the host app's, for
        // extensions) before trusting App Store. iOS-family devices skip this:
        // every non-store install there carries a provisioning profile, and the
        // receipt file's presence should not be load-bearing.
        guard let receiptURL = bundle.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: receiptURL.path) else {
            return .development
        }
#endif
        return .appStore
#endif
    }()

    /// Development / ad-hoc / enterprise builds embed a provisioning profile;
    /// App Store and TestFlight installs do not.
    private static func hasEmbeddedProvisioningProfile(_ bundle: Bundle) -> Bool {
#if os(macOS) || targetEnvironment(macCatalyst)
        // Mac bundles keep the profile at Contents/embedded.provisionprofile,
        // outside the Resources directory that path(forResource:) searches.
        let url = bundle.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile")
        return FileManager.default.fileExists(atPath: url.path)
#else
        return bundle.path(forResource: "embedded", ofType: "mobileprovision") != nil
#endif
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
