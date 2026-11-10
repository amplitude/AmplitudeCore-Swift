import Foundation
import XCTest
@_spi(Internal) import AmplitudeCore

final class SanitizedErrorTests: XCTestCase {
    private let secret = "private-user@example.com?token=private-token"

    func testNSErrorPreservesStandardDomainsAndCodes() {
        let cases = [(NSURLErrorDomain, -1009), (NSCocoaErrorDomain, 260),
                     (NSPOSIXErrorDomain, 13), (NSOSStatusErrorDomain, -50)]
        for (domain, code) in cases {
            let result = SanitizedError(sanitizing: NSError(domain: domain, code: code))
            XCTAssertEqual(result.kind, "NSError")
            XCTAssertEqual(result.message, "domain=\(domain), code=\(code)")
            XCTAssertEqual(result.description, "NSError: domain=\(domain), code=\(code)")
        }
    }

    func testNSErrorPreservesCustomAndEmptyDomains() {
        // Domains are metadata, not redacted text. This is an explicit policy boundary.
        for domain in ["com.customer.transport", ""] {
            let result = SanitizedError(sanitizing: NSError(domain: domain, code: 42))
            XCTAssertEqual(result.message, "domain=\(domain), code=42")
        }
    }

    func testNSErrorPreservesFullIntegerCodeRange() {
        for code in [Int.min, -1, 0, 1, Int.max] {
            let result = SanitizedError(sanitizing: NSError(domain: "test", code: code))
            XCTAssertEqual(result.message, "domain=test, code=\(code)")
        }
    }

    func testNSErrorOmitsAllUserInfoIncludingUnderlyingErrors() {
        let underlying = NSError(domain: "private-underlying-domain", code: 999,
                                 userInfo: [NSLocalizedDescriptionKey: secret])
        let error = NSError(domain: NSCocoaErrorDomain, code: 260, userInfo: [
            NSLocalizedDescriptionKey: secret,
            NSLocalizedFailureReasonErrorKey: secret,
            NSLocalizedRecoverySuggestionErrorKey: secret,
            NSDebugDescriptionErrorKey: secret,
            NSFilePathErrorKey: "/private/\(secret)",
            NSURLErrorFailingURLErrorKey: URL(string: "https://example.com/private?token=private-token")!,
            NSUnderlyingErrorKey: underlying,
            "private-key": ["nested": secret]
        ])
        let result = SanitizedError(sanitizing: error)
        XCTAssertEqual(result.description, "NSError: domain=\(NSCocoaErrorDomain), code=260")
        XCTAssertFalse(result.description.contains(secret))
        XCTAssertFalse(result.description.contains("private-underlying-domain"))
    }

    func testNSErrorSubclassKeepsDynamicTypeWithoutReadingDescriptionsOrUserInfo() {
        let result = SanitizedError(sanitizing: UnreadableNSError(domain: "test.domain", code: 17))
        XCTAssertEqual(result.kind, "UnreadableNSError")
        XCTAssertEqual(result.message, "domain=test.domain, code=17")
    }

    func testNativeURLErrorPreservesDomainAndCodeWithoutUserInfo() {
        let error = URLError(.notConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: secret,
                                                               NSURLErrorFailingURLStringErrorKey: secret])
        let result = SanitizedError(sanitizing: error)
        XCTAssertEqual(result.kind, "NSError")
        XCTAssertEqual(result.message, "domain=\(NSURLErrorDomain), code=-1009")
    }

    func testNativeURLErrorPreservesUnrecognizedCode() {
        let result = SanitizedError(sanitizing: URLError(URLError.Code(rawValue: -98765)))
        XCTAssertEqual(result.message, "domain=\(NSURLErrorDomain), code=-98765")
    }

    func testNativeCocoaErrorPreservesDomainAndCodeWithoutUserInfo() {
        let error = CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: secret,
                                                            NSLocalizedDescriptionKey: secret])
        let result = SanitizedError(sanitizing: error)
        XCTAssertEqual(result.kind, "NSError")
        XCTAssertEqual(result.message, "domain=\(NSCocoaErrorDomain), code=260")
    }

    func testNativeCocoaErrorPreservesUnrecognizedCode() {
        let result = SanitizedError(sanitizing: CocoaError(CocoaError.Code(rawValue: 98765)))
        XCTAssertEqual(result.message, "domain=\(NSCocoaErrorDomain), code=98765")
    }

    func testNativePOSIXErrorPreservesDomainAndCode() {
        let result = SanitizedError(sanitizing: POSIXError(.EACCES))
        XCTAssertEqual(result.kind, "NSError")
        XCTAssertEqual(result.message, "domain=\(NSPOSIXErrorDomain), code=\(EACCES)")
    }

    func testFoundationErrorsAlreadyBridgedToNSErrorKeepDomainAndCode() {
        let errors: [NSError] = [URLError(.timedOut) as NSError,
                                 CocoaError(.fileWriteOutOfSpace) as NSError,
                                 POSIXError(.EACCES) as NSError]
        for error in errors {
            let result = SanitizedError(sanitizing: error)
            XCTAssertEqual(result.message, "domain=\(error.domain), code=\(error.code)")
        }
    }

    func testEncodingErrorOmitsValueDescriptionKeysAndUnderlyingErrorAtEveryDepth() {
        for depth in [0, 1, 4, 100] {
            let context = EncodingError.Context(codingPath: codingPath(depth), debugDescription: secret,
                                                underlyingError: UnreadableSwiftError())
            let result = SanitizedError(sanitizing: EncodingError.invalidValue(UnreadableValue(), context))
            XCTAssertEqual(result.kind, "EncodingError.invalidValue")
            XCTAssertEqual(result.message, "codingPathDepth=\(depth)")
            XCTAssertFalse(result.description.contains(secret))
        }
    }

    func testDecodingTypeMismatchOmitsExpectedTypeAndContextContent() {
        assertDecodingError(kind: "DecodingError.typeMismatch") { .typeMismatch(UnreadableValue.self, $0) }
    }

    func testDecodingValueNotFoundOmitsExpectedTypeAndContextContent() {
        assertDecodingError(kind: "DecodingError.valueNotFound") { .valueNotFound(UnreadableValue.self, $0) }
    }

    func testDecodingKeyNotFoundDoesNotReadTheMissingKey() {
        assertDecodingError(kind: "DecodingError.keyNotFound") { .keyNotFound(UnreadableCodingKey(), $0) }
    }

    func testDecodingDataCorruptedOmitsContextContent() {
        assertDecodingError(kind: "DecodingError.dataCorrupted") { .dataCorrupted($0) }
    }

    func testRealJSONEncoderFailureDoesNotExposeDictionaryKeysOrValues() throws {
        do {
            _ = try JSONEncoder().encode([secret: Double.infinity])
            XCTFail("Expected a non-finite number encoding error")
        } catch {
            let result = SanitizedError(sanitizing: error)
            XCTAssertEqual(result.kind, "EncodingError.invalidValue")
            XCTAssertEqual(result.message, "codingPathDepth=1")
            XCTAssertFalse(result.description.contains(secret))
        }
    }

    func testRealJSONDecoderFailureDoesNotExposeDictionaryKeysOrValues() throws {
        let data = try JSONSerialization.data(withJSONObject: [secret: secret])
        do {
            _ = try JSONDecoder().decode([String: Int].self, from: data)
            XCTFail("Expected a decoding type mismatch")
        } catch {
            let result = SanitizedError(sanitizing: error)
            XCTAssertEqual(result.kind, "DecodingError.typeMismatch")
            XCTAssertEqual(result.message, "codingPathDepth=1")
            XCTAssertFalse(result.description.contains(secret))
        }
    }

    func testUnknownSwiftErrorDoesNotInvokeDescriptionLocalizationOrReflection() {
        let result = SanitizedError(sanitizing: UnreadableSwiftError())
        XCTAssertEqual(result.kind, "UnreadableSwiftError")
        XCTAssertEqual(result.message, "")
        XCTAssertEqual(result.description, "UnreadableSwiftError")
    }

    func testUnknownCustomNSErrorIsNotBridgedOrInspected() {
        let result = SanitizedError(sanitizing: UnreadableCustomNSError())
        XCTAssertEqual(result.description, "UnreadableCustomNSError")
    }

    func testUnknownEnumDoesNotExposeItsCaseOrAssociatedValues() {
        let result = SanitizedError(sanitizing: UnknownError.payload(secret, UnreadableValue()))
        XCTAssertEqual(result.description, "UnknownError")
    }

    func testUnknownClassErrorDoesNotExposeStoredProperties() {
        let result = SanitizedError(sanitizing: UnknownClassError(value: secret))
        XCTAssertEqual(result.description, "UnknownClassError")
    }

    func testUnknownGenericErrorHasTypeContextWithoutInstanceContent() {
        let result = SanitizedError(sanitizing: UnknownGenericError(value: secret))
        XCTAssertEqual(result.description, "UnknownGenericError<String>")
    }

    func testAuditedErrorSuppliesItsOwnSummaryWithoutFormattingOriginalError() {
        let result = SanitizedError(sanitizing: AuditedError.rejected(status: 429, body: secret))
        XCTAssertEqual(result.kind, "AuditedError.rejected")
        XCTAssertEqual(result.message, "status=429")
    }

    func testAuditedWrapperSanitizesUnderlyingNSError() {
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 260,
                              userInfo: [NSLocalizedDescriptionKey: secret])
        let result = SanitizedError(sanitizing: AuditedError.wrapped(wrapped, path: secret))
        XCTAssertEqual(result.description, "AuditedError.wrapped: NSError: domain=\(NSCocoaErrorDomain), code=260")
    }

    func testAuditedWrapperSanitizesUnderlyingEncodingError() {
        let wrapped = EncodingError.invalidValue(secret, .init(codingPath: codingPath(2), debugDescription: secret))
        let result = SanitizedError(sanitizing: AuditedError.wrapped(wrapped, path: secret))
        XCTAssertEqual(result.description, "AuditedError.wrapped: EncodingError.invalidValue: codingPathDepth=2")
    }

    func testNestedAuditedWrappersRetainCategoriesWithoutPayloads() {
        let inner = AuditedError.wrapped(UnreadableSwiftError(), path: secret)
        let result = SanitizedError(sanitizing: AuditedError.wrapped(inner, path: secret))
        XCTAssertEqual(result.description, "AuditedError.wrapped: AuditedError.wrapped: UnreadableSwiftError")
    }

    func testAuditedNSErrorSubclassTakesPrecedenceOverDefaultNSErrorSummary() {
        let result = SanitizedError(sanitizing: AuditedNSError(domain: "test.domain", code: 12))
        XCTAssertEqual(result.description, "AuditedNSError: operation=write")
    }

    func testAuditedSummaryInitializerPreservesProvidedMetadata() {
        let result = SanitizedError(kind: "BatchUpload", message: "status=503, retry=2, bytes=1024")
        XCTAssertEqual(result.kind, "BatchUpload")
        XCTAssertEqual(result.message, "status=503, retry=2, bytes=1024")
        XCTAssertEqual(result.description, "BatchUpload: status=503, retry=2, bytes=1024")
    }

    func testEmptySummaryDoesNotAddPunctuation() {
        XCTAssertEqual(SanitizedError(kind: "Unknown", message: "").description, "Unknown")
    }

    func testSummaryIsSendable() {
        func requireSendable<T: Sendable>(_ value: T) -> T { value }
        let result = requireSendable(SanitizedError(sanitizing: URLError(.timedOut)))
        XCTAssertEqual(result.message, "domain=\(NSURLErrorDomain), code=-1001")
    }

    func testSummaryDoesNotRetainTheOriginalError() {
        weak var original: NSError?
        let result: SanitizedError = autoreleasepool {
            let error = NSError(domain: "test.domain", code: 7, userInfo: ["payload": secret])
            original = error
            return SanitizedError(sanitizing: error)
        }
        XCTAssertNil(original)
        XCTAssertEqual(result.description, "NSError: domain=test.domain, code=7")
    }

    private func codingPath(_ depth: Int) -> [CodingKey] {
        Array(repeating: UnreadableCodingKey(), count: depth)
    }

    func testSchemaPreservesNestedModelFields() {
        assertPath([PathKey("request"), PathKey("size")],
                   schema: .object(["request": .object(["size": .value])]), expected: "request.size")
    }

    func testSchemaMasksDictionaryKeysEvenWhenTheyMatchKnownFields() {
        for key in [secret, "max", "histogram", "123"] {
            assertPath([PathKey("histogram"), PathKey(key, index: 123), PathKey("max")],
                       schema: .object(["histogram": .dictionary(.object(["max": .value]))]),
                       expected: "histogram.<key>.max")
        }
    }

    func testSchemaDoesNotReadDictionaryKeyNamesOrNumericValues() {
        assertPath([UnreadableCodingKey(), UnreadableCodingKey()],
                   schema: .dictionary(.dictionary(.value)), expected: "<key>.<key>")
    }

    func testSchemaPreservesArrayIndicesWithoutReadingTheirStringValues() {
        assertPath([PathKey("events"), IndexOnlyKey(index: 2), PathKey("time")],
                   schema: .object(["events": .array(.object(["time": .value]))]), expected: "events[2].time")
        assertPath([IndexOnlyKey(index: 0), IndexOnlyKey(index: 123)],
                   schema: .array(.array(.value)), expected: "[0][123]")
    }

    func testSchemaMasksInvalidArrayIndices() {
        for index: Int? in [nil, -1] {
            assertPath([IndexOnlyKey(index: index)], schema: .array(.value), expected: "[?]")
        }
    }

    func testUnknownSchemaFieldStopsInterpretingSubsequentKeys() {
        assertPath([PathKey(secret), UnreadableCodingKey(), UnreadableCodingKey()],
                   schema: .object(["known": .array(.object(["time": .value]))]),
                   expected: "<key>.<key>.<key>")
    }

    func testSchemaValueDoesNotInspectUnexpectedDescendants() {
        assertPath([UnreadableCodingKey(), UnreadableCodingKey()], schema: .value, expected: "<key>.<key>")
    }

    func testSchemaFormatsRootFailure() {
        assertPath([], schema: .object(["count": .value]), expected: "$")
    }

    func testSchemaIncludesMissingModelFieldRatherThanOnlyItsParent() {
        let error = DecodingError.keyNotFound(PathKey("count"),
            .init(codingPath: [PathKey("stats")], debugDescription: secret))
        let result = SanitizedError(sanitizing: error, options: .init(
            codingPathSchema: .object(["stats": .object(["count": .value])])))
        XCTAssertEqual(result.description, "DecodingError.keyNotFound: codingPath=stats.count")
    }

    func testSchemaMasksMissingDictionaryKeyWithoutInspectingIt() {
        let error = DecodingError.keyNotFound(UnreadableCodingKey(),
            .init(codingPath: [], debugDescription: secret))
        let result = SanitizedError(sanitizing: error, options: .init(codingPathSchema: .dictionary(.value)))
        XCTAssertEqual(result.description, "DecodingError.keyNotFound: codingPath=<key>")
    }

    func testSchemaFormatsEveryDecodingCategoryWithoutContextContent() {
        let context = DecodingError.Context(codingPath: [PathKey("count")], debugDescription: secret,
                                            underlyingError: UnreadableSwiftError())
        let errors: [DecodingError] = [.typeMismatch(Int.self, context), .valueNotFound(Int.self, context),
                                       .dataCorrupted(context)]
        for error in errors {
            let result = SanitizedError(sanitizing: error, options: .init(codingPathSchema: .object(["count": .value])))
            XCTAssertEqual(result.message, "codingPath=count")
            XCTAssertFalse(result.description.contains(secret))
        }
    }

    func testSchemaDoesNotChangeNSErrorOrAuditedErrorHandling() {
        let options = SanitizedError.Options(codingPathSchema: .object(["count": .value]))
        let error = UnreadableNSError(domain: "test.domain", code: 17)
        XCTAssertEqual(SanitizedError(sanitizing: error, options: options).description,
                       "UnreadableNSError: domain=test.domain, code=17")
        XCTAssertEqual(SanitizedError(sanitizing: AuditedError.rejected(status: 429, body: secret), options: options).description,
                       "AuditedError.rejected: status=429")
        XCTAssertEqual(SanitizedError(sanitizing: UnreadableSwiftError(), options: options).description, "UnreadableSwiftError")
    }

    func testSchemaFormatsActualJSONEncoderArrayPath() throws {
        do {
            _ = try JSONEncoder().encode([[Double.infinity]])
            XCTFail("Expected encoding failure")
        } catch {
            let result = SanitizedError(sanitizing: error, options: .init(codingPathSchema: .array(.array(.value))))
            XCTAssertEqual(result.description, "EncodingError.invalidValue: codingPath=[0][0]")
        }
    }

    func testSchemaFormatsActualJSONEncoderDictionaryPathWithoutNumericKey() throws {
        do {
            _ = try JSONEncoder().encode(["123456789": Double.infinity])
            XCTFail("Expected encoding failure")
        } catch {
            let result = SanitizedError(sanitizing: error, options: .init(codingPathSchema: .dictionary(.value)))
            XCTAssertEqual(result.description, "EncodingError.invalidValue: codingPath=<key>")
        }
    }

    func testSchemaFormatsActualJSONDecoderMissingField() throws {
        struct Model: Decodable { let count: Int }
        do {
            _ = try JSONDecoder().decode(Model.self, from: Data("{}".utf8))
            XCTFail("Expected missing field")
        } catch {
            let result = SanitizedError(sanitizing: error, options: .init(codingPathSchema: .object(["count": .value])))
            XCTAssertEqual(result.description, "DecodingError.keyNotFound: codingPath=count")
        }
    }

    private func assertPath(_ path: [CodingKey], schema: SanitizedError.CodingPathSchema, expected: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let error = EncodingError.invalidValue(UnreadableValue(), .init(codingPath: path, debugDescription: secret))
        let result = SanitizedError(sanitizing: error, options: .init(codingPathSchema: schema))
        XCTAssertEqual(result.description, "EncodingError.invalidValue: codingPath=\(expected)", file: file, line: line)
        XCTAssertFalse(result.description.contains(secret), file: file, line: line)
    }

    private func assertDecodingError(kind: String, file: StaticString = #filePath, line: UInt = #line,
                                     makeError: (DecodingError.Context) -> DecodingError) {
        for depth in [0, 1, 4, 100] {
            let context = DecodingError.Context(codingPath: codingPath(depth), debugDescription: secret,
                                                underlyingError: UnreadableSwiftError())
            let result = SanitizedError(sanitizing: makeError(context))
            XCTAssertEqual(result.kind, kind, file: file, line: line)
            XCTAssertEqual(result.message, "codingPathDepth=\(depth)", file: file, line: line)
            XCTAssertFalse(result.description.contains(secret), file: file, line: line)
        }
    }
}

// Getters fail the test if the sanitizer even inspects content it should discard.
private struct UnreadableValue: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String { XCTFail("Read payload description"); return "private-value" }
    var debugDescription: String { XCTFail("Read payload debug description"); return "private-value" }
}

private struct UnreadableCodingKey: CodingKey {
    init() { }
    init?(stringValue: String) { self.init() }
    init?(intValue: Int) { self.init() }
    var stringValue: String { XCTFail("Read coding key name"); return "private-key" }
    var intValue: Int? { XCTFail("Read coding key index"); return 42 }
}

private struct PathKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init(_ name: String, index: Int? = nil) { stringValue = name; intValue = index }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { self.init("Index \(intValue)", index: intValue) }
}

private struct IndexOnlyKey: CodingKey {
    let intValue: Int?
    init(index: Int?) { intValue = index }
    init?(stringValue: String) { self.init(index: nil) }
    init?(intValue: Int) { self.init(index: intValue) }
    var stringValue: String { XCTFail("Read array key string"); return "private-key" }
}

private struct UnreadableSwiftError: Error, LocalizedError, CustomStringConvertible,
                                     CustomDebugStringConvertible, CustomReflectable {
    var errorDescription: String? { XCTFail("Read localized description"); return "private-description" }
    var failureReason: String? { XCTFail("Read failure reason"); return "private-reason" }
    var recoverySuggestion: String? { XCTFail("Read recovery suggestion"); return "private-recovery" }
    var helpAnchor: String? { XCTFail("Read help anchor"); return "private-anchor" }
    var description: String { XCTFail("Formatted unknown error"); return "private-description" }
    var debugDescription: String { XCTFail("Debug-formatted unknown error"); return "private-debug" }
    var customMirror: Mirror { XCTFail("Reflected unknown error"); return Mirror(reflecting: 0) }
}

private struct UnreadableCustomNSError: Error, CustomNSError {
    static var errorDomain: String { XCTFail("Bridged custom domain"); return "private-domain" }
    var errorCode: Int { XCTFail("Bridged custom code"); return 42 }
    var errorUserInfo: [String: Any] { XCTFail("Bridged custom userInfo"); return ["private-key": "private-value"] }
}

private class UnreadableNSError: NSError, @unchecked Sendable {
    override var userInfo: [String: Any] { XCTFail("Read NSError userInfo"); return [:] }
    override var localizedDescription: String { XCTFail("Read NSError localizedDescription"); return "private-description" }
    override var description: String { XCTFail("Formatted NSError"); return "private-description" }
    override var debugDescription: String { XCTFail("Debug-formatted NSError"); return "private-debug" }
}

private enum UnknownError: Error { case payload(String, UnreadableValue) }

private final class UnknownClassError: Error {
    let value: String
    init(value: String) { self.value = value }
}

private struct UnknownGenericError<T: Sendable>: Error { let value: T }

private indirect enum AuditedError: SanitizableError, CustomStringConvertible {
    case rejected(status: Int, body: String)
    case wrapped(Error, path: String)

    var description: String { XCTFail("Formatted audited error instead of sanitizing it"); return "private-description" }

    func sanitized() -> SanitizedError {
        switch self {
        case .rejected(let status, _):
            return SanitizedError(kind: "AuditedError.rejected", message: "status=\(status)")
        case .wrapped(let error, _):
            return SanitizedError(kind: "AuditedError.wrapped", message: SanitizedError(sanitizing: error).description)
        }
    }
}

private final class AuditedNSError: UnreadableNSError, SanitizableError, @unchecked Sendable {
    func sanitized() -> SanitizedError {
        SanitizedError(kind: "AuditedNSError", message: "operation=write")
    }
}
