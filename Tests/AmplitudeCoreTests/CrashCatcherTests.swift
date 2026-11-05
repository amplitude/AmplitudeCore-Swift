//
//  CrashCatcherTests.swift
//  AmplitudeCore
//

#if !os(watchOS)

import XCTest
@testable import AmplitudeCore

final class CrashCatcherTests: XCTestCase {

    private static let sigDfl = unsafeBitCast(SIG_DFL, to: UInt.self)
    private static let sigIgn = unsafeBitCast(SIG_IGN, to: UInt.self)

    private let touchedSignals: [Int32] = [SIGPIPE, SIGFPE, SIGBUS, SIGURG]
    private var savedActions: [Int32: sigaction] = [:]

    override func setUp() {
        super.setUp()
        // Other tests may have registered already; start from the process's original dispositions.
        CrashCatcher.unregister()
        for sig in touchedSignals {
            var action = sigaction()
            sigaction(sig, nil, &action)
            savedActions[sig] = action
        }
    }

    override func tearDown() {
        CrashCatcher.unregister()
        CrashCatcher.reraiseDispositionForTesting = nil
        for (sig, var action) in savedActions {
            sigaction(sig, &action, nil)
        }
        super.tearDown()
    }

    func testRegisterDoesNotHandleSIGPIPE() {
        signal(SIGPIPE, SIG_DFL)

        CrashCatcher.register()

        XCTAssertEqual(handlerAddress(SIGPIPE), Self.sigDfl)
    }

    func testRegisterKeepsIgnoredSignalsIgnored() {
        signal(SIGFPE, SIG_IGN)
        signal(SIGBUS, SIG_DFL)

        CrashCatcher.register()

        XCTAssertEqual(handlerAddress(SIGFPE), Self.sigIgn)
        XCTAssertNotEqual(handlerAddress(SIGBUS), Self.sigDfl)
        XCTAssertNotEqual(handlerAddress(SIGBUS), Self.sigIgn)

        CrashCatcher.unregister()

        XCTAssertEqual(handlerAddress(SIGFPE), Self.sigIgn)
        XCTAssertEqual(handlerAddress(SIGBUS), Self.sigDfl)
    }

    func testWriteToClosedPipeSurvivesWhenAppIgnoresSIGPIPE() throws {
        signal(SIGPIPE, SIG_IGN)

        CrashCatcher.register()

        // If SIGPIPE were no longer ignored, the write below would terminate the test process.
        guard handlerAddress(SIGPIPE) == Self.sigIgn else {
            return XCTFail("CrashCatcher.register() replaced the ignored SIGPIPE disposition")
        }

        var fds: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&fds), 0)
        close(fds[0])
        defer { close(fds[1]) }

        var byte: UInt8 = 0
        XCTAssertEqual(write(fds[1], &byte, 1), -1)
        XCTAssertEqual(errno, EPIPE)
    }

    func testReraiseIsDeliveredOnlyAfterTheHandlerReturns() {
        // Stands in for the real chain: our handler calls a previous handler that unblocks every signal
        // (as Firebase Crashlytics does), then re-raises. A recording disposition in place of SIG_DFL keeps
        // the test process alive; SIGURG is ignored by default and doesn't stop LLDB.
        ReraiseProbe.install(SIGURG)

        raise(SIGURG)

        XCTAssertEqual(ReraiseProbe.deliveries, 1)
        XCTAssertFalse(ReraiseProbe.deliveredInsideHandler,
                       "re-raised signal was delivered inside the handler, so the process would die there")
    }

    func testReraiseIsDeliveredWhenTheInterruptedContextBlocksTheSignal() {
        // sigsuspend() restores a mask that blocks SIGURG when it returns, so a re-raised signal left
        // pending would never be delivered.
        ReraiseProbe.install(SIGURG)
        var blocked = sigset_t()
        sigemptyset(&blocked)
        sigaddset(&blocked, SIGURG)
        var previousMask = sigset_t()
        pthread_sigmask(SIG_BLOCK, &blocked, &previousMask)
        defer { pthread_sigmask(SIG_SETMASK, &previousMask, nil) }

        raise(SIGURG)
        var suspendMask = previousMask
        sigdelset(&suspendMask, SIGURG)
        sigsuspend(&suspendMask)

        var pending = sigset_t()
        sigpending(&pending)
        XCTAssertEqual(ReraiseProbe.deliveries, 1)
        XCTAssertEqual(sigismember(&pending, SIGURG), 0, "re-raised signal is stuck pending")
    }

    func testReraiseWithoutContextIsDeliveredImmediately() {
        // Without the interrupted context there is no way to tell whether deferring is safe.
        ReraiseProbe.install(SIGURG, forwardContext: false)

        raise(SIGURG)

        XCTAssertEqual(ReraiseProbe.deliveries, 1)
        XCTAssertTrue(ReraiseProbe.deliveredInsideHandler)
    }

    private func handlerAddress(_ sig: Int32) -> UInt {
        var action = sigaction()
        sigaction(sig, nil, &action)
        return unsafeBitCast(action.__sigaction_u.__sa_handler, to: UInt.self)
    }
}

private enum ReraiseProbe {
    static var outerHandlerFinished = false
    static var deliveries = 0
    static var deliveredInsideHandler = false

    static var forwardContext = true

    /// Installs `outerHandler` for `sig` and makes CrashCatcher re-raise into `recordingDisposition`.
    static func install(_ sig: Int32, forwardContext: Bool = true) {
        self.forwardContext = forwardContext
        outerHandlerFinished = false
        deliveries = 0
        deliveredInsideHandler = false
        CrashCatcher.reraiseDispositionForTesting = recordingDisposition

        var outer = sigaction()
        outer.__sigaction_u.__sa_sigaction = outerHandler
        outer.sa_flags = SA_SIGINFO
        sigemptyset(&outer.sa_mask)
        sigaction(sig, &outer, nil)
    }

    static let recordingDisposition: @convention(c) (Int32) -> Void = { _ in
        deliveries += 1
        if !outerHandlerFinished {
            deliveredInsideHandler = true
        }
    }

    static let outerHandler: @convention(c) (Int32, UnsafeMutablePointer<__siginfo>?, UnsafeMutableRawPointer?) -> Void = { sig, _, context in
        // Crashlytics uses sigprocmask, which on Darwin changes every thread's mask; this thread is enough here.
        var all = sigset_t()
        sigfillset(&all)
        pthread_sigmask(SIG_UNBLOCK, &all, nil)

        CrashCatcher.resetAndReraise(sig, context: forwardContext ? context : nil)
        outerHandlerFinished = true
    }
}

#endif
