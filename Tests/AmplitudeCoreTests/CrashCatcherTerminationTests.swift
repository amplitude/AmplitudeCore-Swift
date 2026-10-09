//
//  CrashCatcherTerminationTests.swift
//  AmplitudeCore
//

#if os(macOS)

import XCTest
@testable import AmplitudeCore

/// Crashes a child process with CrashCatcher registered and checks how it terminated.
///
/// The child is this test bundle re-launched in the xctest runner on `CrashCatcherChildProcessTests`, with
/// its own home directory (`CFFIXED_USER_HOME`) so its crash report never touches the real one. Before
/// registering, the child installs a previous handler that behaves like Firebase Crashlytics' (unblocks
/// every signal, records, returns), so the chaining path is exercised as well.
///
/// The child's handlers append one character per event to a marker file:
/// `p` previous handler ran, `s`/`o` re-delivered on the same/another thread, `i`/`a` re-raised signal
/// arrived inside/after CrashCatcher's handler, `r` control returned to the crash site.
final class CrashCatcherTerminationTests: XCTestCase {

    func testAbortTerminatesWithSIGABRT() throws {
        let result = try XCTUnwrap(runChild(.abort))

        XCTAssertEqual(result.terminationSignal, SIGABRT, result.diagnostics)
        XCTAssertEqual(result.markers, "p", result.diagnostics)
        XCTAssertTrue(result.report?.hasPrefix("Fatal Signal: SIGABRT") ?? false, result.diagnostics)
    }

    func testRaisedSIGABRTTerminates() throws {
        // Nothing re-delivers a signal sent by raise(), so a handler that just returned would let the app run on.
        let result = try XCTUnwrap(runChild(.raiseAbort))

        XCTAssertEqual(result.terminationSignal, SIGABRT, result.diagnostics)
        XCTAssertEqual(result.markers, "p", result.diagnostics)
    }

    func testNullDereferenceTerminatesWithSIGSEGV() throws {
        // A hardware fault re-executes the faulting instruction; returning with our handler still
        // installed would loop until the timeout.
        let result = try XCTUnwrap(runChild(.nullDereference))

        XCTAssertEqual(result.terminationSignal, SIGSEGV, result.diagnostics)
        XCTAssertEqual(result.markers, "p", result.diagnostics)
        XCTAssertTrue(result.report?.hasPrefix("Fatal Signal: SIGSEGV") ?? false, result.diagnostics)
    }

    func testSwiftTrapTerminates() throws {
        let result = try XCTUnwrap(runChild(.swiftTrap))

        // brk on arm64, ud2 on x86_64
        XCTAssertTrue([SIGTRAP, SIGILL].contains(result.terminationSignal ?? 0), result.diagnostics)
        XCTAssertEqual(result.markers, "p", result.diagnostics)
    }

    func testGCDWorkerFaultIsRedeliveredOnTheFaultingThread() throws {
        // pthread_kill(self) is rejected on GCD worker threads, and raise() then falls back to kill(getpid()),
        // which hands the signal to another thread.
        let result = try XCTUnwrap(runChild(.gcdWorkerFault))

        XCTAssertEqual(result.terminationSignal, SIGSEGV, result.diagnostics)
        XCTAssertEqual(result.markers, "ps", result.diagnostics)
    }

    func testSoftwareSignalOnNonKillableWorkerTerminates() throws {
        // The main thread blocks the signal, so raise()'s process-directed fallback reaches the GCD worker,
        // where pthread_kill(self) fails and nothing re-executes a faulting instruction.
        let result = try XCTUnwrap(runChild(.softwareSignalOnWorker))

        XCTAssertEqual(result.terminationSignal, CrashChildScenario.softwareSignal, result.diagnostics)
        XCTAssertFalse(result.markers.contains("r"), result.diagnostics)
    }

    func testRestoredMaskBlockingTheSignalIsDeliveredInsideTheHandler() throws {
        // Positive control for the stack check below: sigsuspend() restores a mask that blocks SIGABRT, so
        // the re-raise must be delivered before the handler returns ("i").
        let result = try XCTUnwrap(runChild(.restoredMaskBlocksSignal))

        XCTAssertNil(result.terminationSignal, result.diagnostics)
        XCTAssertEqual(result.markers, "pir", result.diagnostics)
    }

    func testReraiseThroughHandleSignalArrivesAfterItReturns() throws {
        // The child swaps SIG_DFL for a recording disposition, so it survives and exits normally.
        let result = try XCTUnwrap(runChild(.reraiseThroughHandleSignal))

        XCTAssertNil(result.terminationSignal, result.diagnostics)
        XCTAssertEqual(result.markers, "par", result.diagnostics)
        XCTAssertTrue(result.report?.hasPrefix("Fatal Signal: SIGABRT") ?? false, result.diagnostics)
    }

    // MARK: - Child process

    private struct ChildResult {
        var terminationSignal: Int32?
        var markers: String
        var report: String?
        var diagnostics: String
    }

    private func runChild(_ scenario: CrashChildScenario, timeout: TimeInterval = 20) throws -> ChildResult? {
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("crashcatcher-child-\(UUID().uuidString)", isDirectory: true)
        let home = workDirectory.appendingPathComponent("home", isDirectory: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDirectory) }
        let markerURL = workDirectory.appendingPathComponent("markers")
        let stderrURL = workDirectory.appendingPathComponent("stderr.log")
        fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let process = Process()
        process.executableURL = Bundle.main.executableURL
        process.arguments = ["-XCTest", "AmplitudeCoreTests.CrashCatcherChildProcessTests/testCrashScenario",
                             Bundle(for: Self.self).bundlePath]
        // Drop the IDE/test-session configuration so the child runs standalone.
        var environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("XCTest") && $0.key != "DYLD_INSERT_LIBRARIES"
        }
        environment[CrashChildScenario.environmentKey] = scenario.rawValue
        environment[CrashChildScenario.markerPathKey] = markerURL.path
        environment["CFFIXED_USER_HOME"] = home.path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle(forWritingAtPath: stderrURL.path) ?? FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()

        let stderrTail: () -> String = {
            let text = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
            return text.split(separator: "\n").suffix(15).joined(separator: "\n")
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            // SIGKILL: abort() masks SIGTERM, and Process.terminationStatus must not be read while running.
            kill(process.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + 5)
            XCTFail("child did not terminate within \(timeout)s (\(scenario.rawValue))\n\(stderrTail())")
            return nil
        }

        let signalled = process.terminationReason == .uncaughtSignal
        let markers = (try? String(contentsOf: markerURL, encoding: .utf8)) ?? ""
        let reportURL = home.appendingPathComponent(
            "Library/Application Support/com.amplitude.crash_report/com.amplitude.crash_report")
        let report = (try? Data(contentsOf: reportURL)).map { String(decoding: $0, as: UTF8.self) }
        let diagnostics = """
            scenario=\(scenario.rawValue) \(signalled ? "signal" : "exit status")=\(process.terminationStatus) \
            markers=\(markers)
            \(stderrTail())
            """
        return ChildResult(terminationSignal: signalled ? process.terminationStatus : nil,
                           markers: markers,
                           report: report,
                           diagnostics: diagnostics)
    }
}

enum CrashChildScenario: String {
    static let environmentKey = "AMPLITUDE_CRASH_CATCHER_CHILD_SCENARIO"
    static let markerPathKey = "AMPLITUDE_CRASH_CATCHER_CHILD_MARKER"

    case abort
    case raiseAbort
    case nullDereference
    case swiftTrap
    case gcdWorkerFault
    case softwareSignalOnWorker
    case reraiseThroughHandleSignal
    case restoredMaskBlocksSignal

    /// A signal that is never re-executed on return on this architecture (see `isReplayedOnReturn`).
#if arch(x86_64)
    static let softwareSignal = SIGTRAP
#else
    static let softwareSignal = SIGFPE
#endif
}

/// Only does something when launched by `CrashCatcherTerminationTests`.
final class CrashCatcherChildProcessTests: XCTestCase {

    private static var markerPath: UnsafeMutablePointer<CChar>?
    private static var faultingThread: pthread_t?

    /// Async-signal-safe append of one byte to the marker file.
    private static func mark(_ character: Unicode.Scalar) {
        guard let path = markerPath else { return }
        let fd = open(path, O_CREAT | O_WRONLY | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        var byte = UInt8(ascii: character)
        _ = write(fd, &byte, 1)
        close(fd)
    }

    private static let crashlyticsLikeHandler: @convention(c) (Int32, UnsafeMutablePointer<__siginfo>?, UnsafeMutableRawPointer?) -> Void = { _, _, _ in
        var all = sigset_t()
        sigfillset(&all)
        sigprocmask(SIG_UNBLOCK, &all, nil)
        mark("p")
    }

    /// Records which thread the re-delivered signal reached, then lets the next delivery terminate.
    private static let threadRecordingDisposition: @convention(c) (Int32) -> Void = { sig in
        let sameThread = faultingThread.map { pthread_equal($0, pthread_self()) != 0 } ?? false
        mark(sameThread ? "s" : "o")
        signal(sig, SIG_DFL)
    }

    /// Records whether the re-raised signal arrived while CrashCatcher's handler was still on the stack:
    /// a nested delivery shows two signal trampolines, a delivery after the handler returned shows one.
    private static let stackRecordingDisposition: @convention(c) (Int32) -> Void = { _ in
        let trampolines = Thread.callStackSymbols.filter { $0.contains("_sigtramp") }.count
        mark(trampolines >= 2 ? "i" : "a")
    }

    func testCrashScenario() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rawScenario = environment[CrashChildScenario.environmentKey],
              let scenario = CrashChildScenario(rawValue: rawScenario),
              let markerPath = environment[CrashChildScenario.markerPathKey] else {
            throw XCTSkip("Runs only as a child process of CrashCatcherTerminationTests")
        }

        Self.markerPath = strdup(markerPath)
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            var action = sigaction()
            action.__sigaction_u.__sa_sigaction = Self.crashlyticsLikeHandler
            action.sa_flags = SA_SIGINFO
            sigemptyset(&action.sa_mask)
            sigaction(sig, &action, nil)
        }
        switch scenario {
        case .gcdWorkerFault:
            CrashCatcher.reraiseDispositionForTesting = Self.threadRecordingDisposition
        case .reraiseThroughHandleSignal, .restoredMaskBlocksSignal:
            CrashCatcher.reraiseDispositionForTesting = Self.stackRecordingDisposition
        default:
            break
        }
        CrashCatcher.register()

        switch scenario {
        case .abort:
            abort()
        case .raiseAbort, .reraiseThroughHandleSignal:
            raise(SIGABRT)
        case .nullDereference:
            UnsafeMutablePointer<Int>(bitPattern: 0x10)!.pointee = 1
        case .swiftTrap:
            let values = [1]
            _ = values[values.count + markerPath.count]
        case .gcdWorkerFault:
            DispatchQueue.global().async {
                Self.faultingThread = pthread_self()
                UnsafeMutablePointer<Int>(bitPattern: 0x10)!.pointee = 1
            }
            // The parent's timeout bounds this.
            DispatchSemaphore(value: 0).wait()
        case .softwareSignalOnWorker:
            // sigprocmask() is process-wide on Darwin: block the signal on every thread, then unblock it on the
            // worker only, so that raise()'s process-directed fallback has to land there.
            var blocked = sigset_t()
            sigemptyset(&blocked)
            sigaddset(&blocked, CrashChildScenario.softwareSignal)
            sigprocmask(SIG_BLOCK, &blocked, nil)
            DispatchQueue.global().async { [blocked] in
                var workerMask = blocked
                pthread_sigmask(SIG_UNBLOCK, &workerMask, nil)
                raise(CrashChildScenario.softwareSignal)
                sleep(1)
                Self.mark("r")
                exit(0)
            }
            DispatchSemaphore(value: 0).wait()
        case .restoredMaskBlocksSignal:
            var blocked = sigset_t()
            sigemptyset(&blocked)
            sigaddset(&blocked, SIGABRT)
            var previousMask = sigset_t()
            pthread_sigmask(SIG_BLOCK, &blocked, &previousMask)
            raise(SIGABRT)
            var suspendMask = previousMask
            sigdelset(&suspendMask, SIGABRT)
            sigsuspend(&suspendMask)
        }
        Self.mark("r")
    }
}

#endif
