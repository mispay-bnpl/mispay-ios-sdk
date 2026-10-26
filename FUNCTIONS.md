# **MISPay iOS SDK Documentation**

The MISPay iOS SDK enables seamless integration of MIS Pay's Buy-Now-Pay-Later checkout into your iOS application. This document provides detailed instructions for setting up the SDK, creating and starting checkouts, handling results, and troubleshooting errors.

---

## **Table of Contents**

1. [SDK Requirements](#sdk-requirements)
2. [Initialize the SDK](#initialize-the-sdk)
3. [Create and Start a Checkout](#create-and-start-a-checkout)
4. [Handle the Result](#handle-the-result)
5. [Track a Checkout](#track-a-checkout)
6. [Installation in Your App](#installation-in-your-app)
7. [Field Rules & Validation](#field-rules--validation)
8. [Lifecycle Guarantees](#lifecycle-guarantees)
9. [Error Codes](#error-codes)
10. [Legacy API (deprecated)](#legacy-api-deprecated)

---

## **1. SDK Requirements**

To integrate the MISPay SDK into your app, you need the following:

- **App ID (`x-app-id`)** and **App Secret (`x-app-secret`)**: credentials provided by the MIS Pay Technical Team.
- **Environment**: sandbox, production or a custom HTTPS base URL.
- iOS 13+, Xcode 12+, Swift Package Manager.

| Environment | Base URL |
| --- | --- |
| `.sandbox` | `https://api-sandbox.mispay.dev/v1/api/` |
| `.production` | `https://api.mispay.co/v1/api/` |
| `.custom(baseUrl:)` | any HTTPS base URL (private deployment) |

### Example:
```swift
let environment: MISPayEnvironment = .sandbox   // set .production for live, .custom(baseUrl:) for private deployments
```

The SDK has **no third-party dependencies** — it uses only Foundation, CryptoKit and WebKit.

---

## **2. Initialize the SDK**

Before using the SDK, initialize it once per app launch (e.g. in your `AppDelegate`/`SceneDelegate` or root view controller), before `startCheckout(from:…)`. Calling it again replaces the configuration and drops any cached token.

```swift
MISPay.initialize(
    appId: "your-x-app-id",
    appSecret: "your-x-app-secret",
    environment: .sandbox        // .production or .custom(baseUrl: "https://…")
)
```

Precondition-fails when `appId` or `appSecret` is blank.

---

## **3. Create and Start a Checkout**

`MISPay.startCheckout` runs the full documented flow — token → decrypt → start-checkout → hosted checkout WKWebView presented modally from your view controller:

```swift
MISPay.startCheckout(
    from: self,
    request: request,
    onCheckoutStarted: { url, trackId in      // optional — see "Track a Checkout"
        // checkout session created, checkout page about to open
    }
) { result in
    switch result {
    case .success(let token): showSuccess(token)
    case .cancelled:          showCancelled()
    case .failure(let error): showError(error.meCode, error.localizedDescription)
    }
}
```

If `initialize` has not been called, the completion receives `.failure` (nothing is thrown). Validation failures of `request` are **never** thrown — they are delivered as `.failure` on the main thread.

### **Example: Complete Checkout Request**

```swift
let request = CheckoutRequest(
    orderId: "1233-ABCD",                 // your unique order id (mandatory)
    totalPrice: "215",                    // mandatory, numeric string
    shippingAmount: "0",                  // mandatory, numeric string
    vat: "15",                            // mandatory, numeric string
    purchaseAmount: "200",                // totalPrice + shippingAmount + vat - discount
    purchaseCurrency: "SAR",              // mandatory
    lang: "en",                           // "en" or "ar"
    invoiceId: "1234567890",              // optional
    discount: Discount(                   // optional; omit when not applied
        percentage: "15",
        amount: "30",
        voucherName: "MIS-30"
    ),
    customerDetails: CustomerDetails(
        mobileNumber: "+966512345678",    // MANDATORY: 05XXXXXXXX, 9665XXXXXXXX or +9665XXXXXXXX
        id: "customer-id",                // optional
        firstName: "First",               // optional
        lastName: "Last",                 // optional
        email: "customer@example.com"     // optional
    ),
    orderDetails: OrderDetails(items: [
        OrderItem(
            quantity: "2",                // mandatory, numeric string
            unitPrice: "100",             // mandatory, numeric string
            sku: "1234568abcd",           // optional
            nameArabic: "اسم المنتج",     // nameArabic or nameEnglish required
            nameEnglish: "Item name",
            itemUrl: "https://itemurl.com",
            imageUrl: "https://imageurl.com"
        ),
    ]),
    shippingDetails: ShippingDetails(     // optional
        firstName: "First", lastName: "Last",
        countryCode: "966", city: "Riyadh", district: "Riyadh",
        line1: "Address line 1", line2: "Address line 2",
        gpsCoordinates: "41.40338, 2.17403"
    ),
    // Required when your MIS Pay callback URL setting is configured as "Dynamic"
    // (otherwise /start-checkout returns ME97):
    callbackUri: "https://your.server/mispay-callback"
)
```

---

## **4. Handle the Result**

The completion fires exactly once per `startCheckout` call, on the **main thread**:

| Result | Meaning |
| --- | --- |
| `.success(token: String?)` | Customer finished the MIS Pay flow. Verify `token` server-side — it encodes the final outcome of the payment. |
| `.cancelled` | Customer closed the checkout or navigated back past the first page. |
| `.failure(MISPayError)` | Flow failed before or during the pages. `error.meCode` and `error.localizedDescription` carry the cause. |

```swift
MISPay.startCheckout(from: self, request: request) { result in
    switch result {
    case .success(let token):
        // Payment flow finished. Verify token server-side — it encodes the final outcome.
        showSuccess(token)
    case .cancelled:
        // Customer closed the checkout or navigated back past the first page.
        showCancelled()
    case .failure(let error):
        // Validation, network, API, decryption or page-load failure.
        showError(error.meCode, error.localizedDescription)
    }
}
```

---

## **5. Track a Checkout**

`onCheckoutStarted` receives `(url, trackId)` once the checkout session is created. Use `trackId` to poll the authoritative status server-side:

```
GET /track-checkout/{trackId}
```

Statuses: `pending` / `in-progress` / `success` / `canceled` / `error`. This is also the authoritative fallback when your app process is killed during checkout (see [Lifecycle Guarantees](#lifecycle-guarantees)).

---

## **6. Installation in Your App**

### 1. Add the package

In Xcode: **File → Add Packages…** → enter this repository's URL. Add the `mispaysdk` library to your app target.

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://gitlab.core.finbyte.cloud/jouri/mobile/mispay-ios-sdk.git", from: "2.0.0"),
]
```

### 2. Import and initialize

```swift
import mispaysdk

MISPay.initialize(
    appId: "your-x-app-id",
    appSecret: "your-x-app-secret",
    environment: .sandbox
)
```

No manifest permissions are required beyond a standard `NSAppTransportSecurity` HTTPS setup (all MIS Pay endpoints are HTTPS), and no third-party dependencies are pulled in.

---

## **7. Field Rules & Validation**

- All amounts/quantities are **numeric strings** (`"215"`, `"2"`) per the API contract.
- `purchaseAmount` should equal `totalPrice + shippingAmount + vat - discount.amount`;
  a mismatch is logged, never rejected. The server validates the formula and rejects
  mismatches with **ME18**.
- `version` (`"v1.2"`) and `isMobile` (`true`) are set automatically.
- Invalid requests deliver `.failure` with a descriptive message — nothing is sent
  to the API.
- `customerDetails.mobileNumber` is **mandatory** and must match `05XXXXXXXX`,
  `9665XXXXXXXX` or `+9665XXXXXXXX`.
- **Minimum amount:** the API rejects purchases below **SAR 145** (`ME13`).

---

## **8. Lifecycle Guarantees**

- **Exactly-once delivery** — the completion fires exactly once per call, on the
  main thread: token received → `.success`; close or back navigation past the first
  page → `.cancelled`; validation, network, API, decryption or page-load failures →
  `.failure`.
- **One checkout at a time** — a second `startCheckout` while one is in flight
  fails fast with `.failure` instead of mis-delivering results.
- **Page load failures are surfaced** — if the checkout URL fails to load (offline,
  DNS, HTTP error), you receive `.failure`, not a blank screen.
- **Process death** — if iOS terminates your app while the customer is on the MIS Pay
  pages, no in-app result can be delivered. Authoritative fallbacks are server-side:
  your `callbackUri` webhook and `GET /track-checkout/{trackId}` polling.

---

## **9. Error Codes**

Documented by MIS Pay (`doc.mispay.co`):

| Code | Meaning |
| --- | --- |
| ME01 / ME02 | App ID / App Secret not provided |
| ME03 | Merchant application not found (wrong App ID or App Secret) |
| ME04 | Checkout session is invalid |
| ME05 | Transaction not found |
| ME10 | Token not valid (SDK auto-invalidates cache and retries once) |
| ME11 | Session expired (SDK auto-invalidates cache and retries once) |
| ME13 | Amount below the minimum (SAR 145) |
| ME18 | `purchaseAmount` does not match `totalPrice + shippingAmount + vat - discount.amount` (server-validated) |
| ME97 | Invalid request — most commonly a missing `callbackUri` when your account's callback URL is configured as *Dynamic* |
| E9997 | Server-side error (report the `x-trace-id` response header to MIS Pay support) |

---

## **10. Legacy API (deprecated)**

`MISPaySDK(urlString:onMessageReceived:)` from SDK 1.x still works unchanged (raw
checkout URL, message-only callback, no cancel/error delivery) but is deprecated —
migrate to `MISPay.initialize` + `MISPay.startCheckout` for typed results and the
full token → start-checkout flow.

---

## Support

For questions or issues, contact **MIS Pay Integration Support** at [partners-support@mispay.co](mailto:partners-support@mispay.co). When reporting issues, include the `x-trace-id` response header if you captured it.
