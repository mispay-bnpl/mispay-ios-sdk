import Foundation

/// Result of a successful `POST /start-checkout`.
struct StartCheckoutResult: Equatable {
    let url: String
    let trackId: String
}

/// Decrypted content of the `/token` payload.
struct DecryptedToken: Equatable {
    let token: String
    /// Epoch milliseconds; nil when missing/unparsable — treated as expired so the
    /// token is always refreshed rather than trusted forever.
    let expirationMillis: Int64?

    static let expiryMarginMillis: Int64 = 60_000

    func isExpired(nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Bool {
        guard let expirationMillis = expirationMillis else { return true }
        return nowMillis >= expirationMillis - Self.expiryMarginMillis
    }
}

/// Parsing for the MIS Pay JSON envelopes. Success responses carry
/// `{"status":"success","result":…}`; error responses come in two shapes:
/// `{"status":"error : 400","result":"ExceptionType.ME01"}` and
/// `{"status":"error","result":{"code":401,"message":"ME10"}}`.
enum ApiJson {

    static let meCodeRegex = try! NSRegularExpression(pattern: "ME\\d{2}")

    /// Extracts the encrypted token blob from a 200 /token response.
    static func parseEncryptedToken(body: String) throws -> String {
        let root = try parseOrThrow(body: body)
        try requireSuccess(root: root, body: body)
        guard let result = root["result"] as? [String: Any] else {
            throw MISPayError(httpStatus: 200, message: "Malformed /token response: 'result' is not an object")
        }
        guard let token = result["token"] as? String, !token.isEmpty else {
            throw MISPayError(httpStatus: 200, message: "Malformed /token response: 'result.token' is missing")
        }
        return token
    }

    /// Parses the decrypted token JSON `{"token":"…","expiration":"…"}`.
    static func parseDecryptedToken(json: Data) throws -> DecryptedToken {
        let root = try parseOrThrow(body: String(data: json, encoding: .utf8) ?? "")
        guard let token = root["token"] as? String, !token.isEmpty else {
            throw MISPayError(message: "Decrypted token payload is missing 'token'")
        }
        let expiration = (root["expiration"] as? String).flatMap(parseExpirationMillis)
        return DecryptedToken(token: token, expirationMillis: expiration)
    }

    /// Extracts url + trackId from a 200 /start-checkout response.
    static func parseStartCheckout(body: String) throws -> StartCheckoutResult {
        let root = try parseOrThrow(body: body)
        try requireSuccess(root: root, body: body)
        guard let result = root["result"] as? [String: Any] else {
            throw MISPayError(httpStatus: 200, message: "Malformed /start-checkout response: 'result' is not an object")
        }
        guard let url = result["url"] as? String, !url.isEmpty else {
            throw MISPayError(httpStatus: 200, message: "Malformed /start-checkout response: 'result.url' is missing")
        }
        let trackId = (result["trackId"] as? String) ?? ""
        return StartCheckoutResult(url: url, trackId: trackId)
    }

    /// Maps an HTTP error body (either documented error shape) to a typed error.
    static func parseErrorBody(body: String, httpStatus: Int) -> MISPayError {
        guard let data = body.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            let snippet = String(body.prefix(120))
            return MISPayError(
                httpStatus: httpStatus,
                message: "Unexpected non-JSON error response (HTTP \(httpStatus)): \(snippet)"
            )
        }
        if let result = root["result"] as? [String: Any] {
            let message = (result["message"] as? String) ?? ""
            return MISPayError(
                meCode: message.isEmpty ? nil : message,
                httpStatus: httpStatus,
                message: message.isEmpty ? "API error: \(root["status"] ?? "?")" : message
            )
        }
        if let resultString = root["result"] as? String {
            let meCode = firstMeCode(in: resultString)
            return MISPayError(
                meCode: meCode,
                httpStatus: httpStatus,
                message: resultString.isEmpty ? "API error: \(root["status"] ?? "?")" : resultString
            )
        }
        let status = (root["status"] as? String) ?? "?"
        return MISPayError(
            meCode: firstMeCode(in: status),
            httpStatus: httpStatus,
            message: "API error: \(status)"
        )
    }

    // MARK: - Helpers

    private static func requireSuccess(root: [String: Any], body: String) throws {
        guard (root["status"] as? String) == "success" else {
            throw parseErrorBody(body: body, httpStatus: 200)
        }
    }

    private static func parseOrThrow(body: String) throws -> [String: Any] {
        guard let data = body.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw MISPayError(httpStatus: 200, message: "Response is not valid JSON: \(String(body.prefix(120)))")
        }
        return object
    }

    private static func firstMeCode(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = meCodeRegex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    /// ISO-8601 UTC without offset ("2022-12-31T23:59:59Z", the documented format),
    /// with an offset-aware fallback.
    static func parseExpirationMillis(_ value: String) -> Int64? {
        let isoUtc = ISO8601DateFormatter() // strict: requires "Z" designator, no fractional seconds
        if let date = isoUtc.date(from: value) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        let flexible = ISO8601DateFormatter()
        flexible.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = flexible.date(from: value) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        return nil
    }

    /// Formats epoch milliseconds back to the documented expiration format (tests + live probe).
    static func formatExpiration(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}
