import Foundation

/// Opt-in summaries for errors owned by an Amplitude SDK.
///
/// Audit every case and associated value before conforming. Return only SDK-defined
/// categories and non-content metadata such as sizes or counts. Sanitize wrapped
/// errors with `SanitizedError(sanitizing:)`; never interpolate the original error.
/// Do not add conformances to error types owned by Foundation or another library.
@_spi(Internal)
public protocol SanitizableError: Error {
    func sanitized() -> SanitizedError
}

/// An error summary for SDK logs and diagnostic events, independent of the log sink.
///
/// Keeps Foundation error domains/codes and Codable failure categories, but excludes
/// descriptions, userInfo, payloads, paths, coding-key names and underlying errors.
/// Unknown Swift errors expose only their type name. NSError domains are retained
/// verbatim, including custom domains; callers must use domains as identifiers,
/// not as containers for customer data.
@_spi(Internal)
public struct SanitizedError: Sendable, CustomStringConvertible {
    public let kind: String
    public let message: String

    public var description: String {
        message.isEmpty ? kind : "\(kind): \(message)"
    }

    /// Constructs an audited summary. The supplied strings are not redacted.
    /// Use fixed SDK text and already-sanitized metadata, never raw error descriptions.
    public init(kind: String, message: String) {
        self.kind = kind
        self.message = message
    }

    public init(sanitizing error: Error) {
        if let error = error as? SanitizableError {
            self = error.sanitized()
            return
        }

        switch error {
        case let error as EncodingError:
            switch error {
            case .invalidValue(_, let context):
                self.init(kind: "EncodingError.invalidValue", depth: context.codingPath.count)
            @unknown default:
                self.init(kind: "EncodingError", message: "")
            }
        case let error as DecodingError:
            switch error {
            case .typeMismatch(_, let context):
                self.init(kind: "DecodingError.typeMismatch", depth: context.codingPath.count)
            case .valueNotFound(_, let context):
                self.init(kind: "DecodingError.valueNotFound", depth: context.codingPath.count)
            case .keyNotFound(_, let context):
                self.init(kind: "DecodingError.keyNotFound", depth: context.codingPath.count)
            case .dataCorrupted(let context):
                self.init(kind: "DecodingError.dataCorrupted", depth: context.codingPath.count)
            @unknown default:
                self.init(kind: "DecodingError", message: "")
            }
        default:
            let kind = String(describing: type(of: error))
            // `as? NSError` also bridges arbitrary Swift errors, which can invoke
            // customer-defined CustomNSError.userInfo. Check the actual type first.
            // Foundation's URLError, CocoaError and POSIXError wrappers already
            // bridge to NSError when passed as Error on Apple platforms.
            if type(of: error) is NSError.Type {
                let error = error as NSError
                self.init(kind: kind, domain: error.domain, code: error.code)
            } else {
                self.init(kind: kind, message: "")
            }
        }
    }

    private init(kind: String, domain: String, code: Int) {
        self.init(kind: kind, message: "domain=\(domain), code=\(code)")
    }

    private init(kind: String, depth: Int) {
        self.init(kind: kind, message: "codingPathDepth=\(depth)")
    }
}
