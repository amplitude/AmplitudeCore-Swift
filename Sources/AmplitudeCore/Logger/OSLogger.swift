//
//  ConsoleLogger.swift
//
//
//  Created by Marvin Liu on 10/28/22.
//

import OSLog

public final class OSLogger: CoreLogger, Sendable {

    public let logLevel: LogLevel
    private let logger: OSLog

    public init(logLevel: LogLevel = .off) {
        self.logLevel = logLevel
        self.logger = OSLog(subsystem: "Amplitude", category: "Logging")
    }

    public func error(message: String) {
        log(.error, message)
    }

    public func warn(message: String) {
        log(.warn, message)
    }

    public func log(message: String) {
        log(.log, message)
    }

    public func debug(message: String) {
        log(.debug, message)
    }

    public func log(_ logLevel: LogLevel, _ message: String) {
        guard logLevel >= self.logLevel else {
            return
        }

        let logType: OSLogType
        switch logLevel {
        case .debug:
            logType = .debug
        case .log:
            logType = .info
        case .warn:
            logType = .default
        case .error:
            logType = .error
        case .off:
            logType = .error
        }

        os_log("%@: %@", log: logger, type: logType, logLevel.logPrefix, message)
    }
}
