//
//  CoreDevice.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 11/14/25.
//

import Foundation

@MainActor
public class CoreDevice: Sendable {
    var manufacturer: String {
        return "unknown"
    }

    var model: String {
        return "unknown"
    }

    var identifierForVendor: String? {
        return nil
    }

    var os_name: String {
        return "unknown"
    }

    var os_version: String {
        return ""
    }

    var platform: String {
        return "unknown"
    }

    static let current: CoreDevice = {
        #if (os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)) && !AMPLITUDE_DISABLE_UIKIT
            return IOSDevice()
        #elseif os(macOS)
            return MacOSDevice()
        #elseif os(watchOS)
            return WatchOSDevice()
        #else
            return CoreDevice()
        #endif
    }()
}

#if (os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)) && !AMPLITUDE_DISABLE_UIKIT
    import SystemConfiguration
    import UIKit

    internal class IOSDevice: CoreDevice {
        private let device = UIDevice.current
        override var manufacturer: String {
            return "Apple"
        }

        override var model: String {
            return deviceModel()
        }

        override var identifierForVendor: String? {
            return device.identifierForVendor?.uuidString
        }

        override var os_name: String {
            return device.systemName.lowercased()
        }

        override var os_version: String {
            return device.systemVersion
        }

        override var platform: String {
            #if os(tvOS)
                return "tvOS"
            #elseif os(visionOS)
                return "visionOS"
            #elseif targetEnvironment(macCatalyst)
                return "macOS"
            #else
                return "iOS"
            #endif
        }

        private func getPlatformString() -> String? {
            var name: [Int32] = [CTL_HW, HW_MACHINE]
            var size: Int = 0
            guard sysctl(&name, 2, nil, &size, nil, 0) == 0, size > 0 else {
                return nil
            }
            var hw_machine = [CChar](repeating: 0, count: size + 1)
            guard sysctl(&name, 2, &hw_machine, &size, nil, 0) == 0 else {
                return nil
            }
            return String(cString: hw_machine)
        }

        private func deviceModel() -> String {
            let platform = getPlatformString() ?? "unknown"
            return getDeviceModel(platform: platform)
        }
    }
#endif

#if os(macOS)
    import Cocoa

    internal class MacOSDevice: CoreDevice {
        private let device = ProcessInfo.processInfo

        override var manufacturer: String {
            return "Apple"
        }

        override var model: String {
            return deviceModel()
        }

        override var identifierForVendor: String? {
            // apple suggested to use this for receipt validation
            // in MAS, works for this too.
            return macAddress(bsd: "en0")
        }

        override var os_name: String {
            return "macos"
        }

        override var os_version: String {
            return String(
                format: "%ld.%ld.%ld",
                device.operatingSystemVersion.majorVersion,
                device.operatingSystemVersion.minorVersion,
                device.operatingSystemVersion.patchVersion
            )
        }

        override var platform: String {
            return "macOS"
        }

        private func getPlatformString() -> String {
            var systemInfo = utsname()
            uname(&systemInfo)
            let machineMirror = Mirror(reflecting: systemInfo.machine)
            let identifier = machineMirror.children.reduce("") { identifier, element in
                guard let value = element.value as? Int8, value != 0 else { return identifier }
                return identifier + String(UnicodeScalar(UInt8(value)))
            }
            return identifier
        }

        private func deviceModel() -> String {
            let platform = getPlatformString()
            return getDeviceModel(platform: platform)
        }

        private func macAddress(bsd: String) -> String? {
            let MAC_ADDRESS_LENGTH = 6
            let separator = ":"

            var length: size_t = 0
            var buffer: [CChar]

            let bsdIndex = Int32(if_nametoindex(bsd))
            if bsdIndex == 0 {
                return nil
            }
            let bsdData = Data(bsd.utf8)
            var managementInfoBase = [CTL_NET, AF_ROUTE, 0, AF_LINK, NET_RT_IFLIST, bsdIndex]

            if sysctl(&managementInfoBase, 6, nil, &length, nil, 0) < 0 {
                return nil
            }

            buffer = [CChar](
                unsafeUninitializedCapacity: length,
                initializingWith: { buffer, initializedCount in
                    for x in 0..<length { buffer[x] = 0 }
                    initializedCount = length
                }
            )

            if sysctl(&managementInfoBase, 6, &buffer, &length, nil, 0) < 0 {
                return nil
            }

            let infoData = Data(bytes: buffer, count: length)
            let indexAfterMsghdr = MemoryLayout<if_msghdr>.stride + 1
            guard let rangeOfToken = infoData[indexAfterMsghdr...].range(of: bsdData) else {
                return nil
            }
            let lower = rangeOfToken.upperBound
            let upper = lower + MAC_ADDRESS_LENGTH
            let macAddressData = infoData[lower..<upper]
            let addressBytes = macAddressData.map { String(format: "%02x", $0) }
            return addressBytes.joined(separator: separator)
        }
    }
#endif

#if os(watchOS)
    import WatchKit

    internal class WatchOSDevice: CoreDevice {
        private let device = WKInterfaceDevice.current()

        override var manufacturer: String {
            return "Apple"
        }

        override var model: String {
            return deviceModel()
        }

        override var identifierForVendor: String? {
            // apple suggested to use this for receipt validation
            // in MAS, works for this too.
            if #available(watchOS 6.2, *) {
                return device.identifierForVendor?.uuidString
            } else {
                return nil
            }
        }

        override var os_name: String {
            return "watchos"
        }

        override var os_version: String {
            return device.systemVersion
        }

        override var platform: String {
            return "watchOS"
        }

        private func getPlatformString() -> String? {
            var name: [Int32] = [CTL_HW, HW_MACHINE]
            var size: Int = 0
            guard sysctl(&name, 2, nil, &size, nil, 0) == 0, size > 0 else {
                return nil
            }
            var hw_machine = [CChar](repeating: 0, count: size + 1)
            guard sysctl(&name, 2, &hw_machine, &size, nil, 0) == 0 else {
                return nil
            }
            return String(cString: hw_machine)
        }

        private func deviceModel() -> String {
            let platform = getPlatformString() ?? "unknown"
            return getDeviceModel(platform: platform)
        }
    }
#endif

private func getDeviceModel(platform: String) -> String {
    // use server device mapping except for the following exceptions

    if platform == "i386" || platform == "x86_64" {
        return "Simulator"
    }

    if platform.hasPrefix("MacBookAir") {
        return "MacBook Air"
    }

    if platform.hasPrefix("MacBookPro") {
        return "MacBook Pro"
    }

    if platform.hasPrefix("MacBook") {
        return "MacBook"
    }

    if platform.hasPrefix("MacPro") {
        return "Mac Pro"
    }

    if platform.hasPrefix("Macmini") {
        return "Mac Mini"
    }

    if platform.hasPrefix("iMac") {
        return "iMac"
    }

    if platform.hasPrefix("Xserve") {
        return "Xserve"
    }

    return platform
}
