import XCTest
@testable import mispaysdk
import CryptoKit

final class MISPayApiTests: XCTestCase {

    private var api: MISPayApi!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        api = MISPayApi(
            baseUrl: "http://stub.local/v1/api/",
            urlSession: URLSession(configuration: configuration)
        )
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
        super.tearDown()
    }

    // MARK: - /token

    func testFetchTokenSendsGETWithCredentialHeaders() {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/api/token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-app-id"), "app-id-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-app-secret"), "secret-1")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"status":"success","result":{"token":"BLOB123"}}"#.utf8)
            )
        }

        let expectation = expectation(description: "token")
        api.fetchEncryptedToken(appId: "app-id-1", appSecret: "secret-1") { result in
            XCTAssertEqual(try? result.get(), "BLOB123")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testTokenErrorWithStringResultMapsToMECode() {
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                Data(#"{"status":"error : 400","result":"ExceptionType.ME01"}"#.utf8)
            )
        }

        let expectation = expectation(description: "ME01")
        api.fetchEncryptedToken(appId: "a", appSecret: "b") { result in
            if case .failure(let error) = result {
                XCTAssertEqual(error.meCode, "ME01")
                XCTAssertEqual(error.httpStatus, 400)
            } else {
                XCTFail("expected failure")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testNonJSONErrorBodyMapsToTypedError() {
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!,
                Data("<html>Bad gateway</html>".utf8)
            )
        }

        let expectation = expectation(description: "502")
        api.fetchEncryptedToken(appId: "a", appSecret: "b") { result in
            if case .failure(let error) = result {
                XCTAssertEqual(error.httpStatus, 502)
                XCTAssertNil(error.meCode)
                XCTAssertTrue(error.message.contains("Bad gateway"))
            } else {
                XCTFail("expected failure")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    // MARK: - /start-checkout

    func testStartCheckoutSendsPOSTWithBearerAndBody() throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/api/start-checkout")
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer jwt-abc")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-app-id"), "app-id-1")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"status":"success","result":{"url":"https://checkout.example/x","trackId":"tr-1"}}"#.utf8)
            )
        }

        let request = CheckoutRequest(
            orderId: "ORD-1",
            totalPrice: "215",
            shippingAmount: "0",
            vat: "15",
            purchaseAmount: "230",
            purchaseCurrency: "SAR",
            customerDetails: CustomerDetails(mobileNumber: "+966512345678"),
            orderDetails: OrderDetails(items: [
                OrderItem(quantity: "2", unitPrice: "100", nameEnglish: "item"),
            ]),
            callbackUri: "https://merchant.example/cb"
        )
        let body = try request.jsonBody()

        let expectation = expectation(description: "start")
        api.startCheckout(appId: "app-id-1", bearerToken: "jwt-abc", body: body) { result in
            let started = try? result.get()
            XCTAssertEqual(started?.url, "https://checkout.example/x")
            XCTAssertEqual(started?.trackId, "tr-1")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        let sentBody = try XCTUnwrap(StubURLProtocol.lastRequest?.bodyData)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: sentBody) as? [String: Any])
        XCTAssertEqual(sent["orderId"] as? String, "ORD-1")
        XCTAssertEqual(sent["version"] as? String, "v1.2")
        XCTAssertEqual(sent["isMobile"] as? Bool, true)
        XCTAssertEqual(sent["callbackUri"] as? String, "https://merchant.example/cb")
    }

    func testStartCheckoutME10ObjectErrorMapsToTypedError() {
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data(#"{"status":"error","result":{"code":401,"message":"ME10"}}"#.utf8)
            )
        }

        let expectation = expectation(description: "ME10")
        api.startCheckout(appId: "a", bearerToken: "jwt", body: Data("{}".utf8)) { result in
            if case .failure(let error) = result {
                XCTAssertEqual(error.meCode, "ME10")
                XCTAssertEqual(error.httpStatus, 401)
            } else {
                XCTFail("expected failure")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }
    // MARK: - Transport error diagnostics

    func testHintForTimeoutMentionsSandboxIPv4Workaround() {
        let hint = MISPayApi.hint(for: URLError(.timedOut))
        XCTAssertNotNil(hint)
        XCTAssertTrue(hint!.contains("IPv4"), "timeout hint must point at the IPv4 pin workaround")
        XCTAssertTrue(hint!.contains("api-sandbox.mispay.dev"))
    }

    func testHintForOfflineAndHostFailures() {
        XCTAssertEqual(MISPayApi.hint(for: URLError(.notConnectedToInternet)), "device appears to be offline")
        XCTAssertNotNil(MISPayApi.hint(for: URLError(.cannotFindHost)))
        XCTAssertNotNil(MISPayApi.hint(for: URLError(.cannotConnectToHost)))
    }

    func testHintIsNilForOtherErrors() {
        XCTAssertNil(MISPayApi.hint(for: URLError(.badServerResponse)))
        XCTAssertNil(MISPayApi.hint(for: NSError(domain: "some.other.domain", code: 1)))
    }

    func testErrorCodeDescriptionIncludesDomainAndCode() {
        let error = NSError(domain: NSURLErrorDomain, code: -1001)
        let description = MISPayApi.errorCodeDescription(error)
        XCTAssertTrue(description.contains("NSURLErrorDomain"), description)
        XCTAssertTrue(description.contains("-1001"), description)
    }
}

// MARK: - URLProtocol stub

final class StubURLProtocol: URLProtocol {

    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// URLProtocol exposes the body via httpBodyStream for data tasks.
    var bodyData: Data? {
        if let httpBody = httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - TokenManager

final class TokenManagerTests: XCTestCase {

    private let secret = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    private final class FakeDataSource: TokenDataSource, @unchecked Sendable {
        var fetchCount = 0
        let blob: String
        init(blob: String) { self.blob = blob }

        func fetchEncryptedToken(
            appId: String,
            appSecret: String,
            completion: @escaping (Result<String, MISPayError>) -> Void
        ) {
            fetchCount += 1
            completion(.success(blob))
        }
    }

    private func encrypted(_ plainJson: String) -> String {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let nonce = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        let key = SymmetricKey(data: Data(TokenCipher.pbkdf2HmacSHA256(
            password: Array(secret.utf8), salt: Array(salt),
            iterations: 40_000, keyLength: 32
        )))
        let sealed = try! AES.GCM.seal(
            Data(plainJson.utf8), using: key, nonce: AES.GCM.Nonce(data: nonce)
        )
        return (salt + nonce + sealed.ciphertext + sealed.tag).base64EncodedString()
    }

    func testCachesFreshToken() {
        let futureExpiration = ApiJson.formatExpiration(Date().addingTimeInterval(3600))
        let source = FakeDataSource(blob: encrypted(#"{"token":"jwt-1","expiration":"\#(futureExpiration)"}"#))
        let manager = TokenManager(dataSource: source)

        let first = expectation(description: "first")
        manager.getValidToken(appId: "app", appSecret: secret) { result in
            XCTAssertEqual(try? result.get().token, "jwt-1")
            first.fulfill()
        }
        wait(for: [first], timeout: 2)

        let second = expectation(description: "second")
        manager.getValidToken(appId: "app", appSecret: secret) { result in
            XCTAssertEqual(try? result.get().token, "jwt-1")
            second.fulfill()
        }
        wait(for: [second], timeout: 2)
        XCTAssertEqual(source.fetchCount, 1, "fresh token must be cached")
    }

    func testExpiredTokenIsRefetched() {
        let source = FakeDataSource(blob: encrypted(#"{"token":"jwt-old","expiration":"2000-01-01T00:00:00Z"}"#))
        let manager = TokenManager(dataSource: source)

        let first = expectation(description: "first")
        manager.getValidToken(appId: "app", appSecret: secret) { _ in first.fulfill() }
        wait(for: [first], timeout: 2)

        let second = expectation(description: "second")
        manager.getValidToken(appId: "app", appSecret: secret) { _ in second.fulfill() }
        wait(for: [second], timeout: 2)
        XCTAssertEqual(source.fetchCount, 2, "expired token must refetch")
    }

    func testMissingExpirationNeverCaches() {
        let source = FakeDataSource(blob: encrypted(#"{"token":"jwt-no-exp"}"#))
        let manager = TokenManager(dataSource: source)

        let first = expectation(description: "first")
        manager.getValidToken(appId: "app", appSecret: secret) { _ in first.fulfill() }
        wait(for: [first], timeout: 2)

        let second = expectation(description: "second")
        manager.getValidToken(appId: "app", appSecret: secret) { _ in second.fulfill() }
        wait(for: [second], timeout: 2)
        XCTAssertEqual(source.fetchCount, 2, "nil expiration must be treated as expired")
    }

    func testInvalidateForcesRefetch() {
        let futureExpiration = ApiJson.formatExpiration(Date().addingTimeInterval(3600))
        let source = FakeDataSource(blob: encrypted(#"{"token":"jwt-1","expiration":"\#(futureExpiration)"}"#))
        let manager = TokenManager(dataSource: source)

        let first = expectation(description: "first")
        manager.getValidToken(appId: "app", appSecret: secret) { _ in first.fulfill() }
        wait(for: [first], timeout: 2)

        manager.invalidate()

        let second = expectation(description: "second")
        manager.getValidToken(appId: "app", appSecret: secret) { _ in second.fulfill() }
        wait(for: [second], timeout: 2)
        XCTAssertEqual(source.fetchCount, 2)
    }
}
