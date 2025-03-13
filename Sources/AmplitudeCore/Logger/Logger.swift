//
//  Logger.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 1/29/25.
//

import Foundation

@objc(AMPLogLevel)
public enum LogLevelEnum: Int {
    case OFF
    case ERROR
    case WARN
    case LOG
    case DEBUG
}

@objc
public protocol Logger: AnyObject {
    func error(message: String)
    func warn(message: String)
    func log(message: String)
    func debug(message: String)
}
