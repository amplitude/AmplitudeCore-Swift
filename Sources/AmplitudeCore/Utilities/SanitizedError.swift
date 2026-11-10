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
/// descriptions, userInfo, payloads, filesystem paths and underlying errors.
/// Coding paths default to depth only; an audited schema can expose fixed fields
/// and array indices while masking dynamic dictionary keys.
/// Unknown Swift errors expose only their type name. NSError domains are retained
/// verbatim, including custom domains; callers must use domains as identifiers,
/// not as containers for customer data.
@_spi(Internal)
public struct SanitizedError: Sendable, CustomStringConvertible {
    /// Describes an SDK-owned model, never a schema built from customer input.
    /// Unknown fields and dictionary keys are masked. Only array positions expose
    /// integer indices: a numeric dictionary key is still customer content.
    public indirect enum CodingPathSchema: Sendable {
        case object([String: CodingPathSchema])
        case dictionary(CodingPathSchema)
        case array(CodingPathSchema)
        case value

        fileprivate func format(_ path: [CodingKey]) -> String {
            var schema = self
            var result = ""
            for key in path {
                let component: String
                switch schema {
                case .object(let fields):
                    if let index = fields.index(forKey: key.stringValue) {
                        // Emit the audited schema's spelling, not the input key.
                        let field = fields[index]
                        component = field.key
                        schema = field.value
                    } else {
                        component = "<key>"
                        schema = .value
                    }
                case .dictionary(let value):
                    component = "<key>"
                    schema = value
                case .array(let element):
                    if let index = key.intValue, index >= 0 {
                        result += "[\(index)]"
                    } else {
                        result += "[?]"
                    }
                    schema = element
                    continue
                case .value:
                    component = "<key>"
                }
                result += result.isEmpty ? component : ".\(component)"
            }
            return result.isEmpty ? "$" : result
        }
    }

    public struct Options: Sendable {
        public var codingPathSchema: CodingPathSchema?

        public init(codingPathSchema: CodingPathSchema? = nil) {
            self.codingPathSchema = codingPathSchema
        }
    }

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
        self.init(sanitizing: error, options: Options())
    }

    /// Options apply to the built-in summaries. An opted-in SanitizableError owns
    /// its entire summary, including any options used when sanitizing wrapped errors.
    public init(sanitizing error: Error, options: Options) {
        if let error = error as? SanitizableError {
            self = error.sanitized()
            return
        }

        switch error {
        case let error as EncodingError:
            switch error {
            case .invalidValue(_, let context):
                self.init(kind: "EncodingError.invalidValue", path: context.codingPath, options: options)
            @unknown default:
                self.init(kind: "EncodingError", message: "")
            }
        case let error as DecodingError:
            switch error {
            case .typeMismatch(_, let context):
                self.init(kind: "DecodingError.typeMismatch", path: context.codingPath, options: options)
            case .valueNotFound(_, let context):
                self.init(kind: "DecodingError.valueNotFound", path: context.codingPath, options: options)
            case .keyNotFound(let key, let context):
                // Codable's context identifies the parent; include the missing
                // field only when the caller supplied a schema to sanitize it.
                let path = options.codingPathSchema == nil ? context.codingPath : context.codingPath + [key]
                self.init(kind: "DecodingError.keyNotFound", path: path, options: options)
            case .dataCorrupted(let context):
                self.init(kind: "DecodingError.dataCorrupted", path: context.codingPath, options: options)
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

    private init(kind: String, path: [CodingKey], options: Options) {
        if let schema = options.codingPathSchema {
            self.init(kind: kind, message: "codingPath=\(schema.format(path))")
        } else {
            self.init(kind: kind, message: "codingPathDepth=\(path.count)")
        }
    }
}
