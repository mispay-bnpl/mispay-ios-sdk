import XCTest
@testable import mispaysdk
import CryptoKit
#if canImport(CommonCrypto)
import CommonCrypto
#endif

final class TokenCipherTests: XCTestCase {

    // 64 hex chars — realistic merchant secret shape.
    private let secret64 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    private let arbitrarySecret = "some-arbitrary-passphrase"

    // MARK: - PBKDF2 correctness

    func testPBKDF2MatchesCommonCrypto() throws {
        try checkPBKDF2(secret: secret64, salt: Array("0123456789abcdef".utf8))
        try checkPBKDF2(secret: arbitrarySecret, salt: Array((0..<16).map { UInt8($0) }))
    }

    private func checkPBKDF2(secret: String, salt: [UInt8]) throws {
        #if canImport(CommonCrypto)
        let iterations = 40_000
        let expected = [UInt8](unsafeUninitializedCapacity: 32) { buffer, count in
            let secretBytes = Array(secret.utf8)
            let status = CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                secretBytes, secretBytes.count,
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                buffer.baseAddress, 32
            )
            precondition(status == kCCSuccess, "CommonCrypto PBKDF2 failed: \(status)")
            count = 32
        }
        let actual = TokenCipher.pbkdf2HmacSHA256(
            password: Array(secret.utf8), salt: salt,
            iterations: iterations, keyLength: 32
        )
        XCTAssertEqual(Array(expected), actual, "PBKDF2 diverges from CommonCrypto")
        #else
        throw XCTSkip("CommonCrypto not available on this platform")
        #endif
    }

    func testPBKDF2KnownVector() {
        // RFC 6070-style vector adapted for SHA-256 (publicly documented test data):
        // PBKDF2-HMAC-SHA256("password", "salt", 1, 32) =
        // 120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b
        let derived = TokenCipher.pbkdf2HmacSHA256(
            password: Array("password".utf8),
            salt: Array("salt".utf8),
            iterations: 1,
            keyLength: 32
        )
        let hex = derived.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    }

    // MARK: - Blob decryption (confirmed wire format)

    func testDecryptsBlobWith64HexSecret() throws {
        let plain = #"{"token":"jwt-abc","expiration":"2999-01-01T00:00:00Z"}"#
        let blob = try encryptLikeOfficialSdk(plain, secret: secret64)
        let decrypted = try TokenCipher.decrypt(blob, appSecret: secret64)
        XCTAssertEqual(String(data: decrypted, encoding: .utf8), plain)
    }

    func testDecryptsBlobWithArbitraryPassphrase() throws {
        let plain = #"{"token":"jwt-xyz"}"#
        let blob = try encryptLikeOfficialSdk(plain, secret: arbitrarySecret)
        let decrypted = try TokenCipher.decrypt(blob, appSecret: arbitrarySecret)
        XCTAssertEqual(String(data: decrypted, encoding: .utf8), plain)
    }

    func testWrongSecretFailsAuthentication() throws {
        let blob = try encryptLikeOfficialSdk(#"{"token":"jwt"}"#, secret: secret64)
        XCTAssertThrowsError(try TokenCipher.decrypt(blob, appSecret: "wrong-secret-entirely")) { error in
            guard let mispayError = error as? MISPayError else {
                return XCTFail("expected MISPayError, got \(error)")
            }
            XCTAssertTrue(mispayError.message.contains("decryption failed"))
        }
    }

    func testTamperedCiphertextFailsAuthentication() throws {
        var raw = try XCTUnwrap(Data(base64Encoded: encryptLikeOfficialSdk(#"{"token":"jwt"}"#, secret: secret64)))
        raw[raw.count - 1] ^= 0x01
        let tampered = raw.base64EncodedString()
        XCTAssertThrowsError(try TokenCipher.decrypt(tampered, appSecret: secret64))
    }

    func testShortBlobRejected() {
        let short = Data([0x00, 0x01, 0x02]).base64EncodedString()
        XCTAssertThrowsError(try TokenCipher.decrypt(short, appSecret: secret64)) { error in
            XCTAssertTrue((error as? MISPayError)?.message.contains("too short") == true)
        }
    }

    func testInvalidBase64Rejected() {
        XCTAssertThrowsError(try TokenCipher.decrypt("!!!not-base64!!!", appSecret: secret64)) { error in
            XCTAssertTrue((error as? MISPayError)?.message.contains("Base64") == true)
        }
    }

    /// Encrypts exactly like the official MIS Pay SDKs:
    /// Base64( salt[16] ‖ nonce[12] ‖ ciphertext ‖ tag[16] ), PBKDF2-HMAC-SHA256
    /// with 40 000 iterations as the AES-256-GCM key.
    private func encryptLikeOfficialSdk(_ plain: String, secret: String) throws -> String {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let nonce = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        let key = SymmetricKey(data: Data(TokenCipher.pbkdf2HmacSHA256(
            password: Array(secret.utf8), salt: Array(salt),
            iterations: 40_000, keyLength: 32
        )))
        let sealed = try AES.GCM.seal(
            Data(plain.utf8), using: key,
            nonce: AES.GCM.Nonce(data: nonce)
        )
        let blob = salt + nonce + sealed.ciphertext + sealed.tag
        return blob.base64EncodedString()
    }
}
