import Foundation

/// Order information sent to `POST /start-checkout`.
///
/// All monetary and numeric values are `String`s by contract with the MIS Pay API
/// (e.g. `"215"`, `"2"`). Optional fields are nil-able and are omitted from the JSON
/// when absent. `validate()` must pass before the request is sent;
/// `MISPay.startCheckout` enforces this and surfaces violations as
/// `MISPayResult.failure`.
///
/// `version` is always serialized as `"v1.2"` and `isMobile` as `true` — fixed by the
/// API contract.
public struct CheckoutRequest {

    // MARK: Mandatory scalars
    public var orderId: String
    public var totalPrice: String
    public var shippingAmount: String
    public var vat: String
    /// `totalPrice + shippingAmount + vat - discount.amount`; a mismatch is logged,
    /// never rejected (rounding is the merchant's call).
    public var purchaseAmount: String
    public var purchaseCurrency: String
    /// `"en"` or `"ar"`.
    public var lang: String

    // MARK: Optional scalars
    public var invoiceId: String?
    public var serialNumber: String?
    public var discount: Discount?
    public var shippingDetails: ShippingDetails?
    /// Required when your MIS Pay callback URL setting is configured as *Dynamic*
    /// (otherwise /start-checkout answers ME97).
    public var callbackUri: String?

    // MARK: Mandatory objects
    public var customerDetails: CustomerDetails
    public var orderDetails: OrderDetails

    public init(
        orderId: String,
        totalPrice: String,
        shippingAmount: String,
        vat: String,
        purchaseAmount: String,
        purchaseCurrency: String,
        lang: String = "en",
        invoiceId: String? = nil,
        serialNumber: String? = nil,
        discount: Discount? = nil,
        customerDetails: CustomerDetails,
        orderDetails: OrderDetails,
        shippingDetails: ShippingDetails? = nil,
        callbackUri: String? = nil
    ) {
        self.orderId = orderId
        self.totalPrice = totalPrice
        self.shippingAmount = shippingAmount
        self.vat = vat
        self.purchaseAmount = purchaseAmount
        self.purchaseCurrency = purchaseCurrency
        self.lang = lang
        self.invoiceId = invoiceId
        self.serialNumber = serialNumber
        self.discount = discount
        self.customerDetails = customerDetails
        self.orderDetails = orderDetails
        self.shippingDetails = shippingDetails
        self.callbackUri = callbackUri
    }

    // MARK: - Validation

    /// Throws `MISPayError` with a merchant-readable message on any violation.
    public func validate() throws {
        try requireNonBlank("orderId", orderId)
        try requireNumeric("totalPrice", totalPrice)
        try requireNumeric("shippingAmount", shippingAmount)
        try requireNumeric("vat", vat)
        try requireNumeric("purchaseAmount", purchaseAmount)
        try requireNonBlank("purchaseCurrency", purchaseCurrency)
        guard lang == "en" || lang == "ar" else {
            throw MISPayError(message: "lang must be 'en' or 'ar' (got '\(lang)')")
        }
        if let callbackUri = callbackUri {
            guard callbackUri.hasPrefix("http://") || callbackUri.hasPrefix("https://") else {
                throw MISPayError(message: "callbackUri must be an http(s) URL (got '\(callbackUri)')")
            }
        }
        guard Self.mobileNumberRegex.matches(customerDetails.mobileNumber) else {
            throw MISPayError(
                message: "customerDetails.mobileNumber format is invalid " +
                    "(got '\(customerDetails.mobileNumber)'). " +
                    "Accepted: 05XXXXXXXX, 9665XXXXXXXX, +9665XXXXXXXX"
            )
        }
        guard !orderDetails.items.isEmpty else {
            throw MISPayError(message: "orderDetails.items must contain at least one item")
        }
        for (index, item) in orderDetails.items.enumerated() {
            let label = "orderDetails.items[\(index)]"
            try requireNumeric("\(label).quantity", item.quantity)
            try requireNumeric("\(label).unitPrice", item.unitPrice)
            guard item.nameArabic != nil || item.nameEnglish != nil else {
                throw MISPayError(message: "\(label) needs nameArabic or nameEnglish (at least one)")
            }
        }
    }

    /// Builds the exact JSON body for /start-checkout; nil optionals are omitted
    /// entirely. Calls `validate()` first.
    public func jsonBody() throws -> Data {
        try validate()

        var body: [String: Any] = [
            "orderId": orderId,
            "totalPrice": totalPrice,
            "shippingAmount": shippingAmount,
            "vat": vat,
            "purchaseAmount": purchaseAmount,
            "purchaseCurrency": purchaseCurrency,
            "lang": lang,
            "version": Self.apiVersion,
            "customerDetails": customerDetails.jsonObject(),
            "orderDetails": orderDetails.jsonObject(),
            "isMobile": true,
        ]
        body["invoiceId"] = invoiceId
        body["serialNumber"] = serialNumber
        body["discount"] = discount?.jsonObject()
        body["shippingDetails"] = shippingDetails?.jsonObject()
        body["callbackUri"] = callbackUri

        return try JSONSerialization.data(withJSONObject: body)
    }

    /// Soft purchase-amount check: non-nil warning when
    /// `totalPrice + shippingAmount + vat - discount.amount` differs from
    /// `purchaseAmount` by more than 0.01.
    public func amountConsistencyIssue() -> String? {
        guard let expected = computedPurchaseAmount(),
              let actual = Decimal(string: purchaseAmount) else { return nil }
        let delta = expected - actual
        if abs(delta) > Decimal(string: "0.01")! {
            return "purchaseAmount (\(purchaseAmount)) does not match " +
                "totalPrice+shippingAmount+vat-discount (\(expected))"
        }
        return nil
    }

    private func computedPurchaseAmount() -> Decimal? {
        guard let total = Decimal(string: totalPrice),
              let shipping = Decimal(string: shippingAmount),
              let vat = Decimal(string: vat) else { return nil }
        let discountAmount = discount?.amount.flatMap { Decimal(string: $0) } ?? 0
        return total + shipping + vat - discountAmount
    }

    private func requireNonBlank(_ name: String, _ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MISPayError(message: "\(name) is mandatory")
        }
    }

    private func requireNumeric(_ name: String, _ value: String) throws {
        try requireNonBlank(name, value)
        // Foundation's Decimal(string:) is lenient (parses "12a" as 12); enforce a
        // strict plain-numeric shape instead: optional sign, digits, optional fraction.
        guard Self.numericRegex.matches(value) else {
            throw MISPayError(message: "\(name) must be a numeric string (got '\(value)')")
        }
    }

    // MARK: Constants

    /// Fixed API version required by the MIS Pay contract.
    public static let apiVersion = "v1.2"

    private static let mobileNumberRegex = NSRegularExpressionValidator(
        pattern: "^(?:05\\d{8}|9665\\d{8}|\\+9665\\d{8})$"
    )

    private static let numericRegex = NSRegularExpressionValidator(
        pattern: "^[+-]?\\d+(\\.\\d+)?$"
    )
}

/// Minimal regex wrapper (Foundation's NSRegularExpression on Apple platforms).
private struct NSRegularExpressionValidator {
    private let regex: NSRegularExpression

    init(pattern: String) {
        regex = try! NSRegularExpression(pattern: pattern)
    }

    func matches(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}

// MARK: - Nested models

/// Discount applied to the order. All fields optional; nils are omitted.
public struct Discount: Sendable {
    public var percentage: String?
    public var amount: String?
    public var voucherName: String?

    public init(percentage: String? = nil, amount: String? = nil, voucherName: String? = nil) {
        self.percentage = percentage
        self.amount = amount
        self.voucherName = voucherName
    }

    func jsonObject() -> [String: Any] {
        ["percentage": percentage, "amount": amount, "voucherName": voucherName]
            .compactMapValues { $0 }
    }
}

/// Customer details. `mobileNumber` is mandatory and format-checked.
public struct CustomerDetails: Sendable {
    public var mobileNumber: String
    public var id: String?
    public var firstName: String?
    public var lastName: String?
    public var email: String?

    public init(
        mobileNumber: String,
        id: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil
    ) {
        self.mobileNumber = mobileNumber
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
    }

    func jsonObject() -> [String: Any] {
        var object: [String: Any] = ["mobileNumber": mobileNumber]
        object["id"] = id
        object["firstName"] = firstName
        object["lastName"] = lastName
        object["email"] = email
        return object.compactMapValues { $0 }
    }
}

/// Ordered items; must contain at least one `OrderItem`.
public struct OrderDetails: Sendable {
    public var items: [OrderItem]

    public init(items: [OrderItem]) {
        self.items = items
    }

    func jsonObject() -> [String: Any] {
        ["items": items.map { $0.jsonObject() }]
    }
}

/// A single ordered item. `quantity` and `unitPrice` are mandatory numeric strings;
/// at least one of `nameArabic`/`nameEnglish` is required.
public struct OrderItem: Sendable {
    public var quantity: String
    public var unitPrice: String
    public var id: String?
    public var sku: String?
    public var nameArabic: String?
    public var nameEnglish: String?
    public var itemUrl: String?
    public var imageUrl: String?

    public init(
        quantity: String,
        unitPrice: String,
        id: String? = nil,
        sku: String? = nil,
        nameArabic: String? = nil,
        nameEnglish: String? = nil,
        itemUrl: String? = nil,
        imageUrl: String? = nil
    ) {
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.id = id
        self.sku = sku
        self.nameArabic = nameArabic
        self.nameEnglish = nameEnglish
        self.itemUrl = itemUrl
        self.imageUrl = imageUrl
    }

    func jsonObject() -> [String: Any] {
        var object: [String: Any] = [
            "quantity": quantity,
            "unitPrice": unitPrice,
        ]
        object["id"] = id
        object["sku"] = sku
        object["nameArabic"] = nameArabic
        object["nameEnglish"] = nameEnglish
        object["itemUrl"] = itemUrl
        object["imageUrl"] = imageUrl
        return object.compactMapValues { $0 }
    }
}

/// Shipping address details. All fields optional.
public struct ShippingDetails: Sendable {
    public var firstName: String?
    public var lastName: String?
    public var countryCode: String?
    public var city: String?
    public var district: String?
    public var line1: String?
    public var line2: String?
    public var gpsCoordinates: String?

    public init(
        firstName: String? = nil,
        lastName: String? = nil,
        countryCode: String? = nil,
        city: String? = nil,
        district: String? = nil,
        line1: String? = nil,
        line2: String? = nil,
        gpsCoordinates: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.countryCode = countryCode
        self.city = city
        self.district = district
        self.line1 = line1
        self.line2 = line2
        self.gpsCoordinates = gpsCoordinates
    }

    func jsonObject() -> [String: Any] {
        [
            "firstName": firstName,
            "lastName": lastName,
            "countryCode": countryCode,
            "city": city,
            "district": district,
            "line1": line1,
            "line2": line2,
            "gpsCoordinates": gpsCoordinates,
        ].compactMapValues { $0 }
    }
}
