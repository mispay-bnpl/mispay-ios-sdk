import XCTest
@testable import mispaysdk

/// Exhaustive contract test mirroring the official MIS Pay parameter table
/// (https://doc.mispay.co/docs/endpoints, "Start Checkout Process", S.No 1-41).
final class CheckoutRequestTests: XCTestCase {

    // MARK: - Mandatory fields

    func testMandatoryScalarFieldsPresentAsStrings() throws {
        let json = try jsonObject(of: docsExample())
        XCTAssertEqual(json["orderId"] as? String, "1233-ABCD")        // S1
        XCTAssertEqual(json["totalPrice"] as? String, "215")           // S3
        XCTAssertEqual(json["shippingAmount"] as? String, "0")         // S4
        XCTAssertEqual(json["vat"] as? String, "15")                   // S5
        XCTAssertEqual(json["purchaseAmount"] as? String, "200")       // S10
        XCTAssertEqual(json["purchaseCurrency"] as? String, "SAR")     // S11
        XCTAssertEqual(json["lang"] as? String, "en")                  // S12
        // Numeric-as-string proof: these must be JSON strings, not numbers.
        ["totalPrice", "shippingAmount", "vat", "purchaseAmount"].forEach {
            XCTAssertTrue(json[$0] is String, "\($0) must serialize as a JSON string")
        }
    }

    func testVersionIsFixed() throws {                                             // S13
        XCTAssertEqual(try jsonObject(of: docsExample())["version"] as? String, "v1.2")
    }

    func testCustomerDetailsMandatoryMobileNumber() throws {                       // S15, S19
        let customer = try XCTUnwrap(jsonObject(of: docsExample())["customerDetails"] as? [String: Any])
        XCTAssertEqual(customer["mobileNumber"] as? String, "+966512345678")
    }

    func testOrderDetailsItemsArray() throws {                                     // S21, S22
        let order = try XCTUnwrap(jsonObject(of: docsExample())["orderDetails"] as? [String: Any])
        let items = try XCTUnwrap(order["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0]["quantity"] as? String, "2")                        // S27
        XCTAssertEqual(items[0]["unitPrice"] as? String, "100")                    // S28
        XCTAssertEqual(items[0]["nameArabic"] as? String, "item name in arabic")   // S25
        XCTAssertEqual(items[0]["nameEnglish"] as? String, "item name in english") // S26
    }

    func testIsMobileIsBooleanTrue() throws {                                      // S40
        XCTAssertEqual(try jsonObject(of: docsExample())["isMobile"] as? Bool, true)
    }

    // MARK: - Optional fields present when set

    func testDiscountFieldsWhenSet() throws {                                      // S6-S9
        let discount = try XCTUnwrap(jsonObject(of: docsExample())["discount"] as? [String: Any])
        XCTAssertEqual(discount["percentage"] as? String, "15")
        XCTAssertEqual(discount["amount"] as? String, "30")
        XCTAssertEqual(discount["voucherName"] as? String, "MIS-30")
    }

    func testInvoiceIdSerialNumberCallbackUriWhenSet() throws {                    // S2, S14, S41
        var request = docsExample()
        request.serialNumber = "SN-001"
        request.callbackUri = "https://merchant.example/cb"
        let json = try jsonObject(of: request)
        XCTAssertEqual(json["invoiceId"] as? String, "1234567890")
        XCTAssertEqual(json["serialNumber"] as? String, "SN-001")
        XCTAssertEqual(json["callbackUri"] as? String, "https://merchant.example/cb")
    }

    func testOptionalCustomerItemShippingFieldsWhenSet() throws {                  // S16-18,20,23,24,29,30,31-39
        let json = try jsonObject(of: docsExample())
        let customer = try XCTUnwrap(json["customerDetails"] as? [String: Any])
        XCTAssertEqual(customer["id"] as? String, "customer ID")
        XCTAssertEqual(customer["firstName"] as? String, "first name")
        XCTAssertEqual(customer["lastName"] as? String, "last name")
        XCTAssertEqual(customer["email"] as? String, "testemail@gmail.com")
        let item = try XCTUnwrap((json["orderDetails"] as? [String: Any])?["items"] as? [[String: Any]])[0]
        XCTAssertEqual(item["id"] as? String, "OR12345")
        XCTAssertEqual(item["sku"] as? String, "1234568abcd")
        XCTAssertEqual(item["itemUrl"] as? String, "https://itemurl.com")
        XCTAssertEqual(item["imageUrl"] as? String, "https://imagurle.com")
        let shipping = try XCTUnwrap(json["shippingDetails"] as? [String: Any])
        XCTAssertEqual(shipping["countryCode"] as? String, "96")
        XCTAssertEqual(shipping["city"] as? String, "riyadh")
        XCTAssertEqual(shipping["gpsCoordinates"] as? String, "41.40338, 2.17403")
    }

    // MARK: - Omission when nil

    func testEveryOptionalFieldOmittedWhenNil() throws {
        let json = try jsonObject(of: minimalExample())
        ["invoiceId", "discount", "serialNumber", "shippingDetails", "callbackUri"].forEach {
            XCTAssertNil(json[$0], "\($0) must be omitted when nil")
        }
        let customer = try XCTUnwrap(json["customerDetails"] as? [String: Any])
        ["id", "firstName", "lastName", "email"].forEach {
            XCTAssertNil(customer[$0], "customerDetails.\($0) must be omitted")
        }
        let item = try XCTUnwrap((json["orderDetails"] as? [String: Any])?["items"] as? [[String: Any]])[0]
        ["id", "sku", "itemUrl", "imageUrl", "nameArabic"].forEach {
            XCTAssertNil(item[$0], "items[0].\($0) must be omitted")
        }
    }

    func testNoNullValuesAnywhereInBody() throws {
        let json = try jsonObject(of: docsExample())
        func assertNoNulls(_ object: [String: Any], _ path: String) {
            object.forEach { key, value in
                if let nested = value as? [String: Any] {
                    assertNoNulls(nested, "\(path).\(key)")
                } else if let list = value as? [[String: Any]] {
                    list.enumerated().forEach { assertNoNulls($1, "\(path).\(key)[\($0)]") }
                } else if value is NSNull {
                    XCTFail("null at \(path).\(key)")
                }
            }
        }
        assertNoNulls(json, "root")
    }

    // MARK: - Validation

    func testAcceptedMobileFormats() throws {
        for mobile in ["0512345678", "966512345678", "+966512345678"] {
            var request = minimalExample()
            request.customerDetails.mobileNumber = mobile
            XCTAssertNoThrow(try request.validate())
        }
    }

    func testValidationFailures() {
        var request = docsExample()

        request.orderId = " "
        assertValidationMessage(request, contains: "orderId")

        request = docsExample(); request.totalPrice = "12a"
        assertValidationMessage(request, contains: "totalPrice")

        request = docsExample(); request.lang = "fr"
        assertValidationMessage(request, contains: "lang")

        request = docsExample(); request.customerDetails.mobileNumber = "12345"
        assertValidationMessage(request, contains: "mobileNumber")

        request = docsExample(); request.orderDetails = OrderDetails(items: [])
        assertValidationMessage(request, contains: "items")

        request = docsExample()
        request.orderDetails = OrderDetails(
            items: [OrderItem(quantity: "1", unitPrice: "10")]
        )
        assertValidationMessage(request, contains: "items[0]")

        request = docsExample(); request.callbackUri = "ftp://example.com"
        assertValidationMessage(request, contains: "callbackUri")
    }

    func testAmountConsistency() {
        XCTAssertNil(docsExample().amountConsistencyIssue())
        var request = docsExample()
        request.purchaseAmount = "999"
        XCTAssertNotNil(request.amountConsistencyIssue())
        // Mismatch is a warning, never a rejection:
        XCTAssertNoThrow(try request.validate())
    }

    func testLangArAccepted() throws {
        var request = docsExample()
        request.lang = "ar"
        XCTAssertEqual(try jsonObject(of: request)["lang"] as? String, "ar")
    }

    // MARK: - Helpers

    private func assertValidationMessage(_ request: CheckoutRequest, contains fragment: String) {
        XCTAssertThrowsError(try request.validate()) { error in
            let message = (error as? MISPayError)?.message ?? error.localizedDescription
            XCTAssertTrue(message.contains(fragment), "expected '\(fragment)' in: \(message)")
        }
    }

    private func jsonObject(of request: CheckoutRequest) throws -> [String: Any] {
        let data = try request.jsonBody()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func docsExample() -> CheckoutRequest {
        CheckoutRequest(
            orderId: "1233-ABCD",
            totalPrice: "215",
            shippingAmount: "0",
            vat: "15",
            purchaseAmount: "200",
            purchaseCurrency: "SAR",
            lang: "en",
            invoiceId: "1234567890",
            discount: Discount(percentage: "15", amount: "30", voucherName: "MIS-30"),
            customerDetails: CustomerDetails(
                mobileNumber: "+966512345678",
                id: "customer ID",
                firstName: "first name",
                lastName: "last name",
                email: "testemail@gmail.com"
            ),
            orderDetails: OrderDetails(items: [
                OrderItem(
                    quantity: "2",
                    unitPrice: "100",
                    id: "OR12345",
                    sku: "1234568abcd",
                    nameArabic: "item name in arabic",
                    nameEnglish: "item name in english",
                    itemUrl: "https://itemurl.com",
                    imageUrl: "https://imagurle.com"
                ),
            ]),
            shippingDetails: ShippingDetails(
                firstName: "first name",
                lastName: "last name",
                countryCode: "96",
                city: "riyadh",
                district: "riyadh",
                line1: "first line",
                line2: "second line",
                gpsCoordinates: "41.40338, 2.17403"
            )
        )
    }

    private func minimalExample() -> CheckoutRequest {
        CheckoutRequest(
            orderId: "ORD-1",
            totalPrice: "10",
            shippingAmount: "0",
            vat: "0",
            purchaseAmount: "10",
            purchaseCurrency: "SAR",
            customerDetails: CustomerDetails(mobileNumber: "0512345678"),
            orderDetails: OrderDetails(items: [
                OrderItem(quantity: "1", unitPrice: "10", nameEnglish: "widget"),
            ])
        )
    }
}
