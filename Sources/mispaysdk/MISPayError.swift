import Foundation

/// Typed failure surfaced to the merchant through `MISPayResult.failure`.
public struct MISPayError: Error, Sendable {
    /// MIS Pay error code when the API returned one
    /// (ME01 credentials, ME04 session, ME10 invalid token, ME11 expired,
    /// ME13 below minimum amount, ME97 invalid request, …).
    public let meCode: String?
    /// HTTP status of the failing response, or -1 when no response was produced
    /// (network / crypto / validation errors).
    public let httpStatus: Int
    /// Human-readable description (never contains secrets).

    public let message: String

    public init(meCode: String? = nil, httpStatus: Int = -1, message: String) {
        self.meCode = meCode
        self.httpStatus = httpStatus
        self.message = message
    }

    /// Console/log friendly description.
    public var localizedDescription: String {
        var parts = [message]
        if let meCode = meCode { parts.append("ME code: \(meCode)") }
        if httpStatus >= 0 { parts.append("HTTP \(httpStatus)") }
        return parts.joined(separator: " | ")
    }
}
