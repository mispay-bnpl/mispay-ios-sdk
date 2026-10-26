import XCTest
@testable import mispaysdk

/// Live probe against the real sandbox: /token → AES-256-GCM decrypt → /start-checkout.
/// Skipped unless the merchant credentials file exists at
/// ../mispay-android-sdk/app/credentials.properties (gitignored, local only).
final class LiveApiProbeTests: XCTestCase {

    private struct Credentials {
        let appId: String
        let appSecret: String
    }

    private func loadCredentials() throws -> Credentials? {
        let url = URL(fileURLWithPath: #filePath) // .../mispay-ios-sdk/Tests/mispaysdkTests/LiveApiProbeTests.swift
            .deletingLastPathComponent()          // Tests/mispaysdkTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // mispay-ios-sdk
            .deletingLastPathComponent()          // msipay-checkout (repo parent)
            .appendingPathComponent("mispay-android-sdk/app/credentials.properties")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        content
            .split(separator: "\n")
            .compactMap { line -> (String, String)? in
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return (String(parts[0]), String(parts[1]).trimmingCharacters(in: .whitespaces))
            }
            .forEach { values[$0.0] = $0.1 }
        guard let appId = values["MISPAY_APP_ID"], let secret = values["MISPAY_APP_SECRET"],
              !appId.isEmpty, !secret.isEmpty, appId != "REPLACE_ME" else { return nil }
        return Credentials(appId: appId, appSecret: secret)
    }

    func testLiveTokenDecryptAndStartCheckout() throws {
        guard let creds = try loadCredentials() else {
            throw XCTSkip("Sandbox credentials not found at ../mispay-android-sdk/app/credentials.properties")
        }
        let api = MISPayApi(baseUrl: MISPayEnvironment.sandbox.baseUrl)
        let tokenManager = TokenManager(dataSource: api)

        let tokenExpectation = expectation(description: "token fetched + decrypted")
        var jwt: String?
        tokenManager.getValidToken(appId: creds.appId, appSecret: creds.appSecret) { result in
            switch result {
            case .success(let token):
                jwt = token.token
                XCTAssertFalse(token.token.isEmpty, "JWT must not be empty")
            case .failure(let error):
                XCTFail("token step failed: \(error.localizedDescription)")
            }
            tokenExpectation.fulfill()
        }
        wait(for: [tokenExpectation], timeout: 60)
        let jwtToken = try XCTUnwrap(jwt)

        let body = try CheckoutRequest(
            orderId: "IOS-PROBE-\(Int(Date().timeIntervalSince1970))",
            totalPrice: "215",
            shippingAmount: "0",
            vat: "15",
            purchaseAmount: "230",
            purchaseCurrency: "SAR",
            customerDetails: CustomerDetails(mobileNumber: "+966512345678"),
            orderDetails: OrderDetails(items: [
                OrderItem(quantity: "2", unitPrice: "100", nameEnglish: "item"),
            ]),
            callbackUri: "https://example.com/mispay-callback"
        ).jsonBody()

        let startExpectation = expectation(description: "start-checkout")
        api.startCheckout(appId: creds.appId, bearerToken: jwtToken, body: body) { result in
            switch result {
            case .success(let started):
                XCTAssertTrue(started.url.hasPrefix("https://"), "checkout URL expected, got \(started.url)")
                XCTAssertFalse(started.trackId.isEmpty)
            case .failure(let error):
                XCTFail("start-checkout failed: \(error.localizedDescription)")
            }
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 60)
    }
}
