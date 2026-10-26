import Foundation
#if canImport(os)
import os
#endif

/// Lightweight, dependency-free logger used across the SDK and the demo app.
///
/// Every line is prefixed with `MISPaySDK ▸ [category]`, a millisecond timestamp
/// and a level, so long-running steps (e.g. a 30 s request timeout) are easy to
/// attribute in the Xcode console, in `simctl launch --console` output, and in
/// Console.app (unified logging, subsystem `co.mispay.sdk`, on iOS 14+/macOS 11+).
///
/// Redaction rule: never log `appSecret` or full tokens — log a ≤4-char prefix
/// and the length, via `redact(_:)`.
public enum MISPayLog {

    /// Log categories; also the Console.app category for the unified-log sink.
    public enum Category: String {
        case flow
        case network
        case token
        case webview
        case demo
    }

    /// Optional in-process hook — set it to mirror log lines somewhere else
    /// (e.g. an on-screen debug console in a demo app). Called on the emitting thread.
    public static var onLog: ((String) -> Void)?

    private static let subsystem = "co.mispay.sdk"

    /// Info-level log.
    public static func info(_ message: String, category: Category = .flow) {
        emit(message, category: category, isError: false)
    }

    /// Error-level log.
    public static func error(_ message: String, category: Category = .flow) {
        emit(message, category: category, isError: true)
    }

    /// Redacts a secret for logging: keeps a 4-char prefix and the length.
    public static func redact(_ secret: String?) -> String {
        guard let secret = secret, !secret.isEmpty else { return "nil" }
        return "\(secret.prefix(4))… (\(secret.count) chars)"
    }

    private static func emit(_ message: String, category: Category, isError: Bool) {
        let line = format(message, category: category, isError: isError, date: Date())
        print(line)
        onLog?(line)
        #if canImport(os)
        if #available(iOS 14.0, macOS 11.0, *) {
            let logger = Logger(subsystem: subsystem, category: category.rawValue)
            // .public: these lines are deliberately loggable; secrets must never
            // be passed to MISPayLog in the first place (use redact(_:)).
            if isError {
                logger.error("\(line, privacy: .public)")
            } else {
                logger.info("\(line, privacy: .public)")
            }
        }
        #endif
    }

    /// Builds the single-line format. Internal for unit tests.
    static func format(
        _ message: String,
        category: Category,
        isError: Bool,
        date: Date
    ) -> String {
        let level = isError ? "ERROR" : "INFO "
        let stamp = timestampFormatter.string(from: date)
        return "MISPaySDK ▸ [\(category.rawValue)] \(stamp) \(level) \(message)"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
}
