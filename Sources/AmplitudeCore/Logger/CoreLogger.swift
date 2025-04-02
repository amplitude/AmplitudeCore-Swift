//
//  Logger.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 1/29/25.
//

import Foundation

@objc
public enum LogLevel: Int, Comparable {

    case off = 0
    case error = 1
    case warn = 2
    case log = 3
    case debug = 4

    var logPrefix: String {
        switch self {
        case .off:
            return ""
        case .error:
            return "ERROR"
        case .warn:
            return "WARN"
        case .log:
            return "LOG"
        case .debug:
            return "DEBUG"
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

@objc
public protocol CoreLogger: AnyObject {
    func error(message: String)
    func warn(message: String)
    func log(message: String)
    func debug(message: String)
}
