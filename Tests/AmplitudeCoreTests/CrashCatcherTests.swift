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

    private let touchedSignals: [Int32] = [SIGPIPE, SIGFPE, SIGBUS]
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

    private func handlerAddress(_ sig: Int32) -> UInt {
        var action = sigaction()
        sigaction(sig, nil, &action)
        return unsafeBitCast(action.__sigaction_u.__sa_handler, to: UInt.self)
    }
}

#endif
