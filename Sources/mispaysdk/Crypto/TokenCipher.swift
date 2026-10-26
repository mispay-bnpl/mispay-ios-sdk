import Foundation
import CryptoKit

/// Decrypts the encrypted token blob returned by `GET /token` (`result.token`).
///
/// CONFIRMED wire format (verified against the official MIS Pay JS and PHP SDKs —
/// both use identical parameters):
///
///     blob = Base64( salt[16] ‖ nonce[12] ‖ ciphertext ‖ tag[16] )
///     key  = PBKDF2-HMAC-SHA256(password: appSecret UTF-8, salt: salt,
///                                iterations: 40 000, keyLength: 32)
///     AES-256-GCM with the 12-byte nonce and a detached 16-byte tag at the end.
///
/// PBKDF2 is implemented directly over CryptoKit's HMAC (CryptoKit ships no PBKDF2)
/// and is cross-verified against CommonCrypto in the unit tests.
struct TokenCipher {

    enum CipherError: Error {
        case invalidBase64
        case blobTooShort(byteCount: Int)
        case decryptionFailed(byteCount: Int, prefixHex: String)
    }

    /// - Parameters:
    ///   - encryptedToken: Base64 blob from the /token response.
    ///   - appSecret: merchant application secret (`x-app-secret`).
    /// - Returns: the decrypted JSON payload `{"token":"<JWT>","expiration":"…"}` as UTF-8 data.
    static func decrypt(_ encryptedToken: String, appSecret: String) throws -> Data {
        guard let raw = Data(base64Encoded: encryptedToken) else {
            throw MISPayError(message: "Encrypted token is not valid Base64")
        }
        guard raw.count >= saltLength + nonceLength + tagLength + 1 else {
            throw MISPayError(message: "Encrypted token is too short (\(raw.count) bytes; " +
                "expected salt16 + nonce12 + ciphertext + tag16)")
        }

        let salt = raw.prefix(saltLength)
        let nonce = raw.dropFirst(saltLength).prefix(nonceLength)
        let tag = raw.suffix(tagLength)
        let ciphertext = raw.dropFirst(saltLength + nonceLength).dropLast(tagLength)

        let keyBytes = pbkdf2HmacSHA256(
            password: Array(appSecret.utf8),
            salt: Array(salt),
            iterations: pbkdf2Iterations,
            keyLength: keyLengthBytes
        )
        let key = SymmetricKey(data: Data(keyBytes))

        do {
            let sealedBox = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: Data(nonce)),
                ciphertext: Data(ciphertext),
                tag: Data(tag)
            )
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            let prefix = raw.prefix(8).map { String(format: "%02x", $0) }.joined()
            throw MISPayError(
                message: "AES-256-GCM decryption failed (blob \(raw.count) bytes, " +
                    "first bytes \(prefix)…)"
            )
        }
    }

    /// PBKDF2 (RFC 2898) with HMAC-SHA256 over CryptoKit.
    /// Visible for cross-verification tests only.
    static func pbkdf2HmacSHA256(
        password: [UInt8],
        salt: [UInt8],
        iterations: Int,
        keyLength: Int
    ) -> [UInt8] {
        precondition(iterations >= 1, "iterations must be >= 1")
        let key = SymmetricKey(data: Data(password))
        // PRF: HMAC-SHA256(secret, data) via explicit update/finalize.
        func prf(_ bytes: [UInt8]) -> [UInt8] {
            var hmac = HMAC<SHA256>(key: key)
            hmac.update(data: bytes)
            return [UInt8](hmac.finalize())
        }
        let hashLength = 32 // SHA-256
        let blockCount = max(1, (keyLength + hashLength - 1) / hashLength)
        var derived = [UInt8]()

        for block in 1...blockCount {
            let blockIndexBytes: [UInt8] = [
                UInt8((block >> 24) & 0xFF), UInt8((block >> 16) & 0xFF),
                UInt8((block >> 8) & 0xFF), UInt8(block & 0xFF)
            ]
            var u = prf(salt + blockIndexBytes)
            var t = u
            for _ in 1..<iterations {
                u = prf(u)
                for i in 0..<t.count { t[i] ^= u[i] }
            }
            derived.append(contentsOf: t)
        }
        return Array(derived.prefix(keyLength))
    }

    // MARK: - Constants (confirmed format)
    static let pbkdf2Iterations = 40_000
    private static let saltLength = 16
    private static let nonceLength = 12
    private static let tagLength = 16
    private static let keyLengthBytes = 32
}
