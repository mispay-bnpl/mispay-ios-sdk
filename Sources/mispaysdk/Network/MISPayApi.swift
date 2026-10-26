import Foundation

/// Transport seam used by `TokenManager` (and mocked in tests).
protocol TokenDataSource: Sendable {
    /// Calls `GET /token`; completion carries the encrypted blob from `result.token`
    /// on the main-independent URLSession queue.
    func fetchEncryptedToken(
        appId: String,
        appSecret: String,
        completion: @escaping (Result<String, MISPayError>) -> Void
    )
}

/// Minimal HTTP client for the MIS Pay API, built on URLSession with no third-party
/// dependencies. Injectable session enables URLProtocol-based unit testing.
final class MISPayApi: TokenDataSource, @unchecked Sendable {

    private let baseUrl: String
    private let urlSession: URLSession

    init(baseUrl: String, urlSession: URLSession? = nil) {
        self.baseUrl = baseUrl
        if let urlSession = urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = Self.timeoutSeconds
            configuration.timeoutIntervalForResource = Self.timeoutSeconds * 2
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    // MARK: - Endpoints

    func fetchEncryptedToken(
        appId: String,
        appSecret: String,
        completion: @escaping (Result<String, MISPayError>) -> Void
    ) {
        guard let request = request(path: Self.tokenPath, method: "GET") else {
            completion(.failure(MISPayError(message: "Invalid /token URL")))
            return
        }
        request.setValue(appId, forHTTPHeaderField: "x-app-id")
        request.setValue(appSecret, forHTTPHeaderField: "x-app-secret")

        execute(request) { result in
            completion(result.flatMap { body in
                Result { try ApiJson.parseEncryptedToken(body: body) }
                    .mapError { $0 as! MISPayError }
            })
        }
    }

    func startCheckout(
        appId: String,
        bearerToken: String,
        body: Data,
        completion: @escaping (Result<StartCheckoutResult, MISPayError>) -> Void
    ) {
        guard var request = request(path: Self.startCheckoutPath, method: "POST") else {
            completion(.failure(MISPayError(message: "Invalid /start-checkout URL")))
            return
        }
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "authorization")
        request.setValue(appId, forHTTPHeaderField: "x-app-id")
        request.httpBody = body

        execute(request) { result in
            completion(result.flatMap { body in
                Result { try ApiJson.parseStartCheckout(body: body) }
                    .mapError { $0 as! MISPayError }
            })
        }
    }

    // MARK: - Plumbing

    private func request(path: String, method: String) -> NSMutableURLRequest? {
        let trimmedBase = baseUrl.hasSuffix("/")
            ? String(baseUrl.dropLast())
            : baseUrl
        guard let url = URL(string: "\(trimmedBase)/\(path)") else { return nil }
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func execute(
        _ request: NSMutableURLRequest,
        completion: @escaping (Result<String, MISPayError>) -> Void
    ) {
        let method = request.httpMethod ?? "?"
        let urlString = request.url?.absoluteString ?? "?"
        let startedAt = CFAbsoluteTimeGetCurrent()
        let effectiveTimeout = min(
            request.timeoutInterval,
            urlSession.configuration.timeoutIntervalForRequest
        )
        MISPayLog.info(
            "→ \(method) \(urlString) (timeout \(String(format: "%.0f", effectiveTimeout))s)",
            category: .network
        )
        let task = urlSession.dataTask(with: request as URLRequest) { data, response, error in
            let elapsed = String(format: "%.2f", CFAbsoluteTimeGetCurrent() - startedAt)
            if let error = error {
                var line = "← \(method) \(urlString) FAILED after \(elapsed)s: " +
                    "\(error.localizedDescription) [\(Self.errorCodeDescription(error))]"
                if let hint = Self.hint(for: error) {
                    line += " — hint: \(hint)"
                }
                MISPayLog.error(line, category: .network)
                completion(.failure(MISPayError(message: "Network error: \(error.localizedDescription)")))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                MISPayLog.error(
                    "← \(method) \(urlString) INVALID RESPONSE (no HTTPURLResponse) after \(elapsed)s",
                    category: .network
                )
                completion(.failure(MISPayError(message: "Invalid response (no HTTPURLResponse)")))
                return
            }
            let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let byteCount = data?.count ?? 0
            guard (200...299).contains(httpResponse.statusCode) else {
                MISPayLog.error(
                    "← \(method) \(urlString) HTTP \(httpResponse.statusCode) " +
                        "(\(byteCount) bytes, \(elapsed)s) body: \(String(body.prefix(200)))",
                    category: .network
                )
                completion(.failure(ApiJson.parseErrorBody(body: body, httpStatus: httpResponse.statusCode)))
                return
            }
            MISPayLog.info(
                "← \(method) \(urlString) HTTP \(httpResponse.statusCode) (\(byteCount) bytes, \(elapsed)s)",
                category: .network
            )
            completion(.success(body))
        }
        task.resume()
    }

    // MARK: - Error diagnostics (internal for tests)

    /// Short `domain code=…` description of a transport error for log lines.
    static func errorCodeDescription(_ error: Error) -> String {
        let nsError = error as NSError
        var description = "\(nsError.domain) code=\(nsError.code)"
        if let streamCode = (nsError.userInfo["_kCFStreamErrorCodeKey"] as? NSNumber)?.intValue {
            description += " stream=\(streamCode)"
        }
        return description
    }

    /// Human hint for transport failures commonly seen with the MIS Pay sandbox.
    /// Returns nil when there is nothing useful to add.
    static func hint(for error: Error) -> String? {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return nil }
        switch nsError.code {
        case -1001: // NSURLErrorTimedOut
            return "request timed out — against the SANDBOX in the iOS Simulator this is the " +
                "known dual-stack IPv6 stall (see README ▸ Troubleshooting: pin " +
                "api-sandbox.mispay.dev to IPv4 in /etc/hosts, or test on a real device)"
        case -1009: // NSURLErrorNotConnectedToInternet
            return "device appears to be offline"
        case -1003, -1004: // cannotFindHost / cannotConnectToHost
            return "host unreachable — check DNS, VPN/tunnel apps and network"
        default:
            return nil
        }
    }

    // MARK: - Constants

    static let tokenPath = "token"
    static let startCheckoutPath = "start-checkout"
    private static let timeoutSeconds: TimeInterval = 30
}
