//
//  ServerZone.swift
//  Amplitude-Swift
//
//  Created by Chris Leonavicius on 1/28/25.
//

@objc(AMPServerZone)
public enum ServerZone: Int, Sendable {
    case US
    case EU
    @_spi(Internal) case STAGING

    public typealias RawValue = String

    public var rawValue: RawValue {
        switch self {
        case .US:
            return "US"
        case .EU:
            return "EU"
        case .STAGING:
            return "STAGING"
        }
    }

    public init?(rawValue: RawValue) {
        switch rawValue {
        case "US":
            self = .US
        case "EU":
            self = .EU
        case "STAGING":
            self = .STAGING
        default:
            return nil
        }
    }
}
