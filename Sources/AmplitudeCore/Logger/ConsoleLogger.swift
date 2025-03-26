//
//  ConsoleLogger.swift
//
//
//  Created by Marvin Liu on 10/28/22.
//

import OSLog

public final class ConsoleLogger: Logger, @unchecked Sendable {

    public var logLevel: LogLevelEnum
    private var logger: OSLog

    public convenience init(logLevel: Int) {
        self.init(logLevel: LogLevelEnum(rawValue: logLevel) ?? .OFF)
    }

    public init(logLevel: LogLevelEnum = .OFF) {
        self.logLevel = logLevel
        self.logger = OSLog(subsystem: "Amplitude", category: "Logging")
    }

    public func error(message: String) {
        if logLevel.rawValue >= LogLevelEnum.ERROR.rawValue {
            os_log("Error: %@", log: logger, type: .error, message)
        }
    }

    public func warn(message: String) {
        if logLevel.rawValue >= LogLevelEnum.WARN.rawValue {
            os_log("Warn: %@", log: logger, type: .default, message)
        }
    }

    public func log(message: String) {
        if logLevel.rawValue >= LogLevelEnum.LOG.rawValue {
            os_log("Log: %@", log: logger, type: .info, message)
        }
    }

    public func debug(message: String) {
        if logLevel.rawValue >= LogLevelEnum.DEBUG.rawValue {
            os_log("Debug: %@", log: logger, type: .debug, message)
        }
    }
}
