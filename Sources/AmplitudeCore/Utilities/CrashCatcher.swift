//
//  CrashCatcher.swift
//  Amplitude-Swift
//
//  Created by Jin Xu on 10/31/25.
//

import Foundation

/// Internal utility to catch crashes and save crash reports to disk.
///
/// **Registration Order:** For Crashlytics compatibility, call `register()` BEFORE `FirebaseApp.configure()`.
class CrashCatcher {
    private static let fatalSignals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE, SIGTRAP]
    private static var previousSignalHandlers: [Int32: sigaction] = [:]
    private static var isRegistered = false
    private static let registrationLock = NSLock()

    // Pre-allocated for signal-safe access
    private static var crashFilePathBuffer: [CChar] = []
    private static var crashFilePathLength: Int = 0

    private typealias SwiftDemangleFunc = @convention(c) (
        UnsafePointer<CChar>?, Int, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?, UInt32
    ) -> UnsafeMutablePointer<CChar>?

    private static var swiftDemangle: SwiftDemangleFunc? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let sym = dlsym(handle, "swift_demangle") else { return nil }
        return unsafeBitCast(sym, to: SwiftDemangleFunc.self)
    }()

    private static let crashReportFileName = "com.amplitude.crash_report"
    private static let storagePrefix: String = "com.amplitude.crash_report"

    private static var storageDirectory: URL? {
        let fileManager = FileManager.default
        guard let baseDirectory = try? fileManager.url(for: .applicationSupportDirectory,
                                                       in: .userDomainMask,
                                                       appropriateFor: nil,
                                                       create: true) else {
            return nil
        }
        let storageDirectory = baseDirectory.appendingPathComponent(Self.storagePrefix,
                                                                    isDirectory: true)
        try? fileManager.createDirectory(at: storageDirectory,
                                         withIntermediateDirectories: true,
                                         attributes: nil)
        return storageDirectory
    }

    private static var crashReportPath: URL? {
        return storageDirectory?.appendingPathComponent(crashReportFileName)
    }

    /// Checks if there was a crash in the previous session
    static func checkForPreviousCrash() -> String? {
        guard let crashReportPath = crashReportPath,
              FileManager.default.fileExists(atPath: crashReportPath.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: crashReportPath)
            let crashReason = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii)
                ?? String(decoding: data, as: UTF8.self)
            return crashReason.isEmpty ? nil : crashReason
        } catch {
            return nil
        }
    }

    static func clearCrashReport() {
        guard let crashReportPath = crashReportPath else { return }
        try? FileManager.default.removeItem(at: crashReportPath)
    }

    static func getCrashReportPath() -> String? {
        return crashReportPath?.path
    }

    /// Registers signal handlers. Thread-safe. Call once at app launch.
    static func register() {
        registrationLock.lock()
        defer { registrationLock.unlock() }

        guard !isRegistered else { return }

        if let path = crashReportPath?.path {
            crashFilePathBuffer = Array(path.utf8CString)
            crashFilePathLength = crashFilePathBuffer.count - 1
        }

        registerSignalHandlers()
        isRegistered = true
    }

    static func unregister() {
        registrationLock.lock()
        defer { registrationLock.unlock() }

        guard isRegistered else { return }

        for (signal, var action) in previousSignalHandlers {
            sigaction(signal, &action, nil)
        }
        previousSignalHandlers.removeAll()
        isRegistered = false
    }

    // MARK: - Signal Handlers

    private static func registerSignalHandlers() {
        for signal in fatalSignals {
            var action = sigaction()
            var oldAction = sigaction()

            sigaction(signal, nil, &oldAction)
            previousSignalHandlers[signal] = oldAction

            action.__sigaction_u.__sa_sigaction = handleSignal
            action.sa_flags = SA_SIGINFO | SA_ONSTACK
            sigemptyset(&action.sa_mask)
            sigaction(signal, &action, nil)
        }
    }

    private static let handleSignal: @convention(c) (Int32, UnsafeMutablePointer<__siginfo>?, UnsafeMutableRawPointer?) -> Void = { sig, info, context in
        saveSignalCrashReport(sig, info: info)

        // Check if another handler was registered after us
        var currentAction = sigaction()
        sigaction(sig, nil, &currentAction)

        let currentHandler = currentAction.__sigaction_u.__sa_sigaction
        let currentHandlerPtr = unsafeBitCast(currentHandler, to: UInt.self)
        let ourHandlerPtr = unsafeBitCast(handleSignal, to: UInt.self)

        if currentHandler != nil && currentHandlerPtr != ourHandlerPtr {
            currentHandler?(sig, info, context)
        } else {
            // Call previous handler if valid
            let oldHandler = previousSignalHandlers[sig]
            let saHandler = oldHandler?.__sigaction_u.__sa_handler
            let saAction = oldHandler?.__sigaction_u.__sa_sigaction
            let sigDfl = unsafeBitCast(SIG_DFL, to: UInt.self)
            let sigIgn = unsafeBitCast(SIG_IGN, to: UInt.self)

            let actionPtr = unsafeBitCast(saAction, to: UInt.self)
            let handlerPtr = unsafeBitCast(saHandler, to: UInt.self)

            if actionPtr != 0 && actionPtr != sigDfl && actionPtr != sigIgn {
                saAction?(sig, info, context)
            } else if handlerPtr != 0 && handlerPtr != sigDfl && handlerPtr != sigIgn {
                saHandler?(sig)
            }
        }

        // Reset to default and re-raise for proper termination
        var defaultAction = sigaction()
        defaultAction.__sigaction_u.__sa_handler = SIG_DFL
        sigemptyset(&defaultAction.sa_mask)
        defaultAction.sa_flags = 0
        sigaction(sig, &defaultAction, nil)
        raise(sig)
    }

    // MARK: - Crash Report Writing

    private static let signalMarkers: [Int32: StaticString] = [
        SIGABRT: "Fatal Signal: SIGABRT",
        SIGILL: "Fatal Signal: SIGILL",
        SIGSEGV: "Fatal Signal: SIGSEGV",
        SIGFPE: "Fatal Signal: SIGFPE",
        SIGBUS: "Fatal Signal: SIGBUS",
        SIGPIPE: "Fatal Signal: SIGPIPE",
        SIGTRAP: "Fatal Signal: SIGTRAP"
    ]
    private static let signalMarkerUNKNOWN: StaticString = "Fatal Signal: UNKNOWN"
    private static let stackTraceHeader: StaticString = "\nCall Stack:\n"
    private static let binaryImagesHeader: StaticString = "\nBinary Images:\n"
    private static let maxStackFrames = 64
    private static let maxBinaryImages = 64

    private static func saveSignalCrashReport(_ signal: Int32, info: UnsafeMutablePointer<__siginfo>?) {
        guard crashFilePathLength > 0 else { return }

        let signalMarker = signalMarkers[signal] ?? signalMarkerUNKNOWN

        crashFilePathBuffer.withUnsafeBufferPointer { pathBuffer in
            guard let pathPtr = pathBuffer.baseAddress else { return }

            let fd = open(pathPtr, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
            guard fd >= 0 else { return }

            signalMarker.withUTF8Buffer { _ = write(fd, $0.baseAddress, $0.count) }
            writeSignalNumber(fd: fd, signal: signal)

            if let info = info?.pointee {
                writeSignalInfo(fd: fd, code: info.si_code, address: info.si_addr)
            }

            stackTraceHeader.withUTF8Buffer { _ = write(fd, $0.baseAddress, $0.count) }

            var callStack = [UnsafeMutableRawPointer?](repeating: nil, count: maxStackFrames)
            let frameCount = backtrace(&callStack, Int32(maxStackFrames))

            var binaryImages: [(base: UnsafeRawPointer, name: UnsafePointer<CChar>)] = []
            binaryImages.reserveCapacity(maxBinaryImages)

            if frameCount > 0 {
                writeStackFrames(fd: fd, frames: &callStack, count: Int(frameCount), binaryImages: &binaryImages)
            }

            if !binaryImages.isEmpty {
                writeBinaryImages(fd: fd, images: binaryImages)
            }

            fsync(fd)
            close(fd)
        }
    }

    private static func writeStackFrames(fd: Int32, frames: inout [UnsafeMutableRawPointer?], count: Int, binaryImages: inout [(base: UnsafeRawPointer, name: UnsafePointer<CChar>)]) {
        var indexBuffer: [UInt8] = Array(repeating: 0, count: 16)
        var addrBuffer: [UInt8] = Array(repeating: 0, count: 32)
        var offsetBuffer: [UInt8] = Array(repeating: 0, count: 32)

        for i in 0..<count {
            guard let frameAddr = frames[i] else { continue }

            // Frame index
            writeStatic(fd, "  ")
            indexBuffer.withUnsafeMutableBufferPointer { buf in
                let len = formatInt32(Int32(i), buffer: &buf)
                _ = write(fd, buf.baseAddress, len)
            }
            writeStatic(fd, "  ")

            var info = Dl_info()
            let hasInfo = dladdr(frameAddr, &info) != 0

            // Image name + collect for Binary Images section
            if hasInfo, let fname = info.dli_fname {
                if let fbase = info.dli_fbase, binaryImages.count < maxBinaryImages {
                    let basePtr = UnsafeRawPointer(fbase)
                    if !binaryImages.contains(where: { $0.base == basePtr }) {
                        binaryImages.append((base: basePtr, name: fname))
                    }
                }
                writeBasename(fd, fname)
            } else {
                writeStatic(fd, "<unknown>")
            }

            // Address
            writeStatic(fd, "  0x")
            let addr = UInt(bitPattern: frameAddr)
            addrBuffer.withUnsafeMutableBufferPointer { buf in
                let len = formatHex(addr, buffer: &buf)
                _ = write(fd, buf.baseAddress, len)
            }
            writeStatic(fd, "  ")

            // Symbol name + offset
            if hasInfo, let sname = info.dli_sname {
                if let demangled = swiftDemangle?(sname, strlen(sname), nil, nil, 0) {
                    _ = write(fd, demangled, min(strlen(demangled), 200))
                    free(demangled)
                } else {
                    _ = write(fd, sname, min(strlen(sname), 120))
                }

                writeStatic(fd, " + ")
                let offset = addr - UInt(bitPattern: info.dli_saddr)
                offsetBuffer.withUnsafeMutableBufferPointer { buf in
                    let len = formatUInt(offset, buffer: &buf)
                    _ = write(fd, buf.baseAddress, len)
                }
            } else {
                writeStatic(fd, "<unknown>")
            }

            writeStatic(fd, "\n")
        }
    }

    private static func writeBinaryImages(fd: Int32, images: [(base: UnsafeRawPointer, name: UnsafePointer<CChar>)]) {
        var addrBuffer: [UInt8] = Array(repeating: 0, count: 32)

        binaryImagesHeader.withUTF8Buffer { _ = write(fd, $0.baseAddress, $0.count) }

        for image in images {
            writeStatic(fd, "0x")
            addrBuffer.withUnsafeMutableBufferPointer { buf in
                let len = formatHex(UInt(bitPattern: image.base), buffer: &buf)
                _ = write(fd, buf.baseAddress, len)
            }
            writeStatic(fd, "  ")
            _ = write(fd, image.name, strlen(image.name))
            writeStatic(fd, "\n")
        }
    }

    // MARK: - Signal-Safe Helpers

    private static func writeStatic(_ fd: Int32, _ str: StaticString) {
        str.withUTF8Buffer { _ = write(fd, $0.baseAddress, $0.count) }
    }

    private static func writeBasename(_ fd: Int32, _ path: UnsafePointer<CChar>) {
        var lastSlash = path
        var ptr = path
        while ptr.pointee != 0 {
            if ptr.pointee == 0x2F { lastSlash = ptr.advanced(by: 1) }
            ptr = ptr.advanced(by: 1)
        }
        _ = write(fd, lastSlash, min(strlen(lastSlash), 40))
    }

    private static func formatUInt(_ value: UInt, buffer: inout UnsafeMutableBufferPointer<UInt8>) -> Int {
        var v = value
        var idx = buffer.count - 1

        if v == 0 {
            buffer[0] = UInt8(ascii: "0")
            return 1
        }

        while v > 0 && idx >= 0 {
            buffer[idx] = UInt8(ascii: "0") + UInt8(v % 10)
            v /= 10
            idx -= 1
        }

        let start = idx + 1
        let len = buffer.count - start
        for i in 0..<len { buffer[i] = buffer[start + i] }
        return len
    }

    private static func writeSignalNumber(fd: Int32, signal: Int32) {
        var numBuffer: [UInt8] = Array(repeating: 0, count: 32)
        writeStatic(fd, " (")
        numBuffer.withUnsafeMutableBufferPointer { buf in
            let len = formatInt32(signal, buffer: &buf)
            _ = write(fd, buf.baseAddress, len)
        }
        writeStatic(fd, ")")
    }

    private static func writeSignalInfo(fd: Int32, code: Int32, address: UnsafeMutableRawPointer?) {
        var codeBuffer: [UInt8] = Array(repeating: 0, count: 32)
        var addrBuffer: [UInt8] = Array(repeating: 0, count: 32)

        writeStatic(fd, " - code: ")
        codeBuffer.withUnsafeMutableBufferPointer { buf in
            let len = formatInt32(code, buffer: &buf)
            _ = write(fd, buf.baseAddress, len)
        }
        writeStatic(fd, ", address: 0x")
        addrBuffer.withUnsafeMutableBufferPointer { buf in
            let len = formatHex(UInt(bitPattern: address), buffer: &buf)
            _ = write(fd, buf.baseAddress, len)
        }
    }

    private static func formatInt32(_ value: Int32, buffer: inout UnsafeMutableBufferPointer<UInt8>) -> Int {
        var v = value
        var isNegative = false
        if v < 0 { isNegative = true; v = -v }

        var idx = buffer.count - 1
        repeat {
            buffer[idx] = UInt8(ascii: "0") + UInt8(v % 10)
            v /= 10
            idx -= 1
        } while v > 0 && idx >= 0

        if isNegative && idx >= 0 {
            buffer[idx] = UInt8(ascii: "-")
            idx -= 1
        }

        let start = idx + 1
        let len = buffer.count - start
        for i in 0..<len { buffer[i] = buffer[start + i] }
        return len
    }

    private static func formatHex(_ value: UInt, buffer: inout UnsafeMutableBufferPointer<UInt8>) -> Int {
        let hexChars: [UInt8] = Array("0123456789abcdef".utf8)

        var v = value
        var idx = buffer.count - 1

        if v == 0 {
            buffer[0] = UInt8(ascii: "0")
            return 1
        }

        while v > 0 && idx >= 0 {
            buffer[idx] = hexChars[Int(v & 0xF)]
            v >>= 4
            idx -= 1
        }

        let start = idx + 1
        let len = buffer.count - start
        for i in 0..<len { buffer[i] = buffer[start + i] }
        return len
    }
}
