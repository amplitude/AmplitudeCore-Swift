//
//  Logger.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 1/29/25.
//

@objc(AMPLogLevel)
public enum LogLevelEnum: Int {
    case OFF
    case ERROR
    case WARN
    case LOG
    case DEBUG
}

public protocol Logger {
    func error(message: String)
    func warn(message: String)
    func log(message: String)
    func debug(message: String)
}
