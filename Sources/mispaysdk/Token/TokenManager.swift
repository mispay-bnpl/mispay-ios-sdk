import Foundation

/// Fetches, decrypts and caches the /token JWT. Tokens are valid ~8 hours per the
/// MIS Pay documentation; refreshed proactively (60 s before expiry) and on demand
/// after `invalidate()` (called by the SDK when the API answers ME10/ME11).
///
/// The cache is memory-only on purpose: no token or secret is ever persisted.
final class TokenManager: @unchecked Sendable {

    private let dataSource: TokenDataSource
    private let lock = NSLock()
    private var cached: DecryptedToken?

    init(dataSource: TokenDataSource) {
        self.dataSource = dataSource
    }

    /// Returns a non-expired decrypted token, fetching + decrypting when needed.
    func getValidToken(appId: String, appSecret: String, completion: @escaping (Result<DecryptedToken, MISPayError>) -> Void) {
        lock.lock()
        if let cached = cached, !cached.isExpired() {
            lock.unlock()
            MISPayLog.info(
                "token cache hit — \(MISPayLog.redact(cached.token)), " +
                    "expires \(Self.expiryDescription(cached.expirationMillis))",
                category: .token
            )
            completion(.success(cached))
            return
        }
        if let cached = cached {
            lock.unlock()
            MISPayLog.info(
                "token cache expired (was \(Self.expiryDescription(cached.expirationMillis))) — refetching /token",
                category: .token
            )
        } else {
            lock.unlock()
            MISPayLog.info("token cache empty — fetching /token", category: .token)
        }

        dataSource.fetchEncryptedToken(appId: appId, appSecret: appSecret) { result in
            switch result {
            case .failure(let error):
                MISPayLog.error(
                    "token fetch failed [\(error.meCode ?? "no ME code")] HTTP\(error.httpStatus): \(error.localizedDescription)",
                    category: .token
                )
                completion(.failure(error))
            case .success(let encrypted):
                MISPayLog.info("token blob received (\(encrypted.count) chars) — decrypting", category: .token)
                do {
                    let plain = try TokenCipher.decrypt(encrypted, appSecret: appSecret)
                    let token = try ApiJson.parseDecryptedToken(json: plain)
                    self.lock.lock()
                    self.cached = token
                    self.lock.unlock()
                    MISPayLog.info(
                        "token decrypted + cached — \(MISPayLog.redact(token.token)), " +
                            "expires \(Self.expiryDescription(token.expirationMillis))",
                        category: .token
                    )
                    completion(.success(token))
                } catch let error as MISPayError {
                    MISPayLog.error("token processing failed: \(error.localizedDescription)", category: .token)
                    completion(.failure(error))
                } catch {
                    MISPayLog.error("Token processing failed: \(error.localizedDescription)", category: .token)
                    completion(.failure(MISPayError(message: "Token processing failed: \(error.localizedDescription)")))
                }
            }
        }
    }

    /// Drops the cached token; the next `getValidToken` call refetches.
    func invalidate() {
        lock.lock()
        cached = nil
        lock.unlock()
        MISPayLog.info("token cache invalidated (ME10/ME11 path) — next call refetches", category: .token)
    }

    private static func expiryDescription(_ millis: Int64?) -> String {
        guard let millis = millis else { return "unknown (treated as expired)" }
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        return Self.expiryFormatter.string(from: date)
    }

    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
