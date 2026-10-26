# **MISPay iOS SDK Example App**

This repository provides a working example of how to integrate the **MISPay iOS SDK** into an iOS application. The example demonstrates key functionalities and serves as a reference for developers using the MISPay SDK.

The SDK handles the complete documented MIS Pay Buy-Now-Pay-Later checkout flow:

```
MISPay.initialize(appId:appSecret:environment:)            once per app launch
MISPay.startCheckout(from:request:completion:)             per purchase
        │
        ├─ 1. GET /token            (x-app-id + x-app-secret headers)
        ├─ 2. Decrypt token         (AES-256-GCM, PBKDF2-HMAC-SHA256 40 000 iterations — automatic, CryptoKit)
        ├─ 3. Cache JWT             (~8 h validity, auto-refresh on expiry or ME10/ME11)
        ├─ 4. POST /start-checkout  (Bearer JWT + full order body; one automatic retry on ME10/ME11)
        └─ 5. Present result.url    in the MISPay WKWebView (hosted MIS Pay checkout pages)
                │
                ├─ customer completes  →  .success(token)
                ├─ customer closes     →  .cancelled
                └─ any step fails      →  .failure(MISPayError)
```

The completion is always invoked on the **main thread**, exactly **once** per call.

---

## **Features**

- Example integration of the MISPay iOS SDK (Swift Package + runnable demo app).
- Demonstrates the complete payment flow: token → start-checkout → hosted checkout WKWebView.
- Configurable environment for testing (`.sandbox`, `.production` or a custom HTTPS base URL).
- Typed results with MIS Pay error codes (`ME01`–`ME97`, `E9997`) surfaced to your app.

---

## **Requirements**

- **Xcode**: 12 or higher.
- **iOS Deployment Target**: 13+.
- **Swift Package Manager** (built in).
- [xcodegen](https://github.com/yonaskolb/XcodeGen) to generate the demo project (`brew install xcodegen`).
- **Credentials** (`x-app-id`, `x-app-secret`) provided by the MIS Pay Technical Team.

---

## **Setup Instructions**

### **1. Download the Example App**

- Download the project as a ZIP file from the repository, or clone it:

```bash
git clone <this repository URL>
```

- Extract the ZIP file (if downloaded) to a local directory.

### **2. Open the Project in Xcode**

- Generate the Xcode project once (the `DemoApp/MISPayDemo.xcodeproj` is generated, not committed):

```bash
brew install xcodegen        # once
cd DemoApp
xcodegen generate
open MISPayDemo.xcodeproj
```

### **3. Configure Your SDK Credentials**

- Copy the credential template and fill in your sandbox credentials from the MIS Pay Technical Team:

```bash
cp Sources/Credentials.plist Sources/Credentials.local.plist   # then edit values
```

- `DemoApp/Sources/Credentials.local.plist` (gitignored — never commit it):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>MISPAY_APP_ID</key>
    <string>REPLACE_ME</string>
    <key>MISPAY_APP_SECRET</key>
    <string>REPLACE_ME</string>
</dict>
</plist>
```

Without this file the demo shows a "Credentials missing" message and disables the Pay button.

### **4. Verify MISPay SDK Version**

The demo uses the SDK from the local Swift package in this repository (`Package.swift`). For your own app, add the package:

```swift
dependencies: [
    .package(url: "https://gitlab.com/mispay/v1/sdks/mispay-ios-sdk.git", from: "2.0.0"),
]
```

> **Note:** Ensure you use the latest compatible version of the MISPay SDK for your app. The SDK has no third-party dependencies — only Foundation, CryptoKit and WebKit.

### **5. Build and Run the App**

- Select an iPhone simulator (or a real device) and press **⌘R** in Xcode.
- Tap **Pay with MISPay** in the demo to start a sandbox checkout.

---

## **Integrate the SDK Into Your Existing App**

This section is for merchants adding the SDK to their **own** app. To try the flow first, run the example app above.

**Prerequisites**

- Xcode 12 or higher; an app with an iOS **13.0+** deployment target.
- Swift Package Manager (built into Xcode — no CocoaPods/Carthage needed).
- Credentials (`x-app-id`, `x-app-secret`) from the MIS Pay Technical Team.

### **1. Add the Swift Package**

In Xcode: **File → Add Package Dependencies…** → paste the repository URL:

```text
https://gitlab.com/mispay/v1/sdks/mispay-ios-sdk.git
```

Dependency rule: **Up to Next Major from `2.0.0`** (if no version tag is published for your account yet, use the `main` branch rule instead). Add the **mispaysdk** library to your app target.

The SDK has **zero third-party dependencies** — only Foundation, CryptoKit and WebKit — so nothing else is added to your dependency graph. Access to the private repository requires your GitLab credentials (SSH key or access token, as provided by the MIS Pay team).

### **2. Project Setup — Almost Nothing**

No pods, no build scripts, no `Info.plist` entries required: the SDK presents its own full-screen checkout controller and WKWebView storage (localStorage, cookies) works out of the box.

Optional: the checkout pages may request the customer's location. If you want that, add `NSLocationWhenInUseUsageDescription` to your `Info.plist` and request authorization before starting a checkout — checkout works without it.

### **3. Initialize the SDK**

Once per app launch, before the first checkout — e.g. in `application(_:didFinishLaunchingWithOptions:)` or your `App`/`SceneDelegate` init:

```swift
import mispaysdk

MISPay.initialize(
    appId: "YOUR_X_APP_ID",        // from the MIS Pay Technical Team
    appSecret: "YOUR_X_APP_SECRET",
    environment: .sandbox           // .production, or .custom(baseUrl: "https://…")
)
```

`.custom` requires `https://`. Blank credentials intentionally crash (`precondition`) so misconfiguration is caught before release — initialize with real values. Keep the secret out of version control; in production prefer injecting it from your build config or a server handshake rather than hardcoding.

### **4. Build the Order and Start Checkout**

```swift
import mispaysdk   // MISPay, CheckoutRequest and nested models all live in this module

let request = CheckoutRequest(
    orderId: "ORDER-\(Int(Date().timeIntervalSince1970))",  // unique per order
    totalPrice: "215",           // all amounts are numeric STRINGS, by API contract
    shippingAmount: "0",
    vat: "15",
    purchaseAmount: "200",       // must equal totalPrice + shippingAmount + vat − discount.amount
    purchaseCurrency: "SAR",
    lang: "en",                  // "en" or "ar"
    discount: Discount(percentage: "15", amount: "30", voucherName: "MIS-30"),  // optional
    customerDetails: CustomerDetails(
        mobileNumber: "+966520006780",  // mandatory: 05…, 9665… or +9665… format
        firstName: "First", lastName: "Last", email: "customer@example.com"
    ),
    orderDetails: OrderDetails(items: [
        OrderItem(
            quantity: "2", unitPrice: "100",          // mandatory, numeric strings
            nameEnglish: "Item name",                  // nameArabic or nameEnglish required
            id: "OR12345", sku: "1234568abcd",
            itemUrl: "https://itemurl.com", imageUrl: "https://imageurl.com"
        ),
    ]),
    shippingDetails: ShippingDetails(city: "riyadh", district: "riyadh", line1: "street"), // optional
    callbackUri: "https://example.com/mispay-callback"  // required when your MIS Pay callback setting is "Dynamic"
)

MISPay.startCheckout(
    from: self,                     // ⚠ must not already present another view controller
    request: request,
    onCheckoutStarted: { url, trackId in
        // Checkout screen presented — persist trackId for server-side status polling.
    }
) { result in
    switch result {
    case .success(let token):
        verifyTokenServerSide(token)               // see step 5
    case .cancelled:
        show("Customer left the checkout")
    case .failure(let error):
        show("Error \(error.meCode ?? ""): \(error.localizedDescription)")
    }
}
```

Guarantees: the completion runs on the **main thread**, exactly **once** per call. Validation problems are delivered as `.failure` (never thrown). Only one checkout can be active at a time — a second call fails fast with `.failure`. Uninitialized SDK also yields `.failure` (with a clear message), not a crash.

> **Amount formula:** keep `totalPrice + shippingAmount + vat − discount.amount = purchaseAmount` exact — the SDK logs a warning on mismatch and the MIS Pay API **rejects** mismatches with `ME18`.

### **5. Verify the Token Server-Side**

`.success(token)` means the customer finished the MIS Pay pages — the token encodes the payment outcome and **must be verified by your backend** (see [doc.mispay.co](https://doc.mispay.co)). Authoritative fallbacks that work even if your app is killed: your `callbackUri` webhook and `GET /track-checkout/{trackId}` polling with the `trackId` from `onCheckoutStarted`.

### **6. Troubleshooting**

| Symptom / code | Meaning and fix |
| --- | --- |
| `Cannot present the checkout: … already has a presented view controller` | The `from:` controller is already presenting — pass a clean presenter (or dismiss first). |
| `ME01` | Credentials rejected — check `appId`/`appSecret`. |
| `ME04` | Session missing — call `MISPay.initialize` before `startCheckout`. |
| `ME10` / `ME11` | Authorization token invalid/expired — the SDK refreshes and retries once automatically; persistent failures mean credentials/environment mismatch. |
| `ME13` | Order below the minimum amount. |
| `ME18` | Order amounts don't satisfy the purchase-amount formula — fix the amounts. |
| `ME97` | `callbackUri` missing — required for accounts with a Dynamic callback setting. |
| `E9997` | Unexpected MIS Pay server error — retry, and report with the `x-trace-id` header if captured. |
| Sandbox requests time out **in the Simulator** (other sites load fine) | Known IPv6/VPN condition — see the fix near the end of this README. |

**Next steps:** full function reference in [FUNCTIONS.md](FUNCTIONS.md) · official docs: [doc.mispay.co](https://doc.mispay.co)

---

## **Repository Structure**

```
├── README.md                       # Documentation file
├── FUNCTIONS.md                    # Full SDK function reference
├── Package.swift                   # Swift package manifest
├── Sources/mispaysdk/
│   ├── MISPay.swift                # Public entry point
│   ├── MISPayResult.swift          # .success / .cancelled / .failure
│   ├── MISPayError.swift           # Typed error (meCode)
│   ├── MISPayEnvironment.swift     # .sandbox / .production / .custom
│   ├── CheckoutWebViewController.swift  # Checkout WKWebView controller
│   ├── mispaysdk.swift             # Legacy 1.x entry point (deprecated)
│   ├── Crypto/                     # AES-256-GCM token decryption (CryptoKit)
│   ├── Network/                    # /token and /start-checkout client
│   ├── Token/                      # JWT cache (~8 h)
│   └── Model/                      # CheckoutRequest + nested models
├── Tests/mispaysdkTests/           # Unit tests (swift test)
└── DemoApp/
    ├── project.yml                 # xcodegen spec → MISPayDemo.xcodeproj
    └── Sources/
        ├── DemoViewController.swift    # One-screen demo (see Usage)
        ├── DemoCredentials.swift   # Credentials loader
        ├── Credentials.plist       # Committed template (REPLACE_ME)
        └── Credentials.local.plist # Your sandbox credentials (gitignored)
```

---

## **Usage Instructions**

1. Run the demo app and tap **Pay with MISPay** to see the full checkout flow (token → start-checkout → hosted checkout pages → typed result). The demo shows the `trackId` when the checkout opens, the token prefix on success, `CANCELLED` on close/back, and typed errors with ME codes.
2. Refer to `DemoApp/Sources/DemoViewController.swift` for implementation details of the MISPay SDK — it initializes the SDK, builds the docs sample order and handles every result type.
3. To integrate the SDK into your own app, follow [Integrate the SDK Into Your Existing App](#integrate-the-sdk-into-your-existing-app) above and the full function reference in [FUNCTIONS.md](FUNCTIONS.md).
4. To run the SDK unit tests on macOS (includes a live sandbox probe when credentials exist):

```bash
swift test
```

---

## **Important Notes**

- **Do not hardcode sensitive credentials** (e.g., `MISPAY_APP_ID`, `MISPAY_APP_SECRET`) in production apps. This example reads them from a gitignored plist for testing purposes only. Use secure methods, such as the Keychain or server-side configurations, for production environments.
- `DemoApp/Sources/Credentials.local.plist` is **gitignored** — never commit credentials.
- **You can check all the supported functions here: [Functions](FUNCTIONS.md)**

### Requests to the SANDBOX time out in the Simulator (other sites load fine)

This machine-level condition is caused by the sandbox being dual-stack (it publishes
IPv6 AAAA records — production does not) combined with VPN/tunnel network extensions
on the Mac (Tailscale, Proton, iCloud Private Relay): simulator processes can keep
choosing a tunnel IPv6 path that stalls, until the request times out.
`xcrun simctl erase` sometimes helps (resets per-device path state) but it recurs.
Durable fixes, best first:

1. Pin the sandbox host to IPv4 (10-second fix, reversible):
   ```bash
   echo "104.21.12.195 api-sandbox.mispay.dev" | sudo tee -a /etc/hosts
   # undo later: sudo sed -i '' '/api-sandbox/d' /etc/hosts
   ```
2. Quit tunnel apps fully (e.g. Tailscale menu-bar → Quit — its network extension
   stays loaded even when "disconnected").
3. Test on a real device (unaffected) or on the production environment.

Also worth reporting to the MIS Pay team: making the sandbox DNS IPv4-only like
production would eliminate this entire class of failures for developers on
VPN/limited-IPv6 networks.

---

## **Support**

For issues or questions about the MISPay SDK, contact **MIS Pay Technical Team / Integration Support** at [partners-support@mispay.co](mailto:partners-support@mispay.co)

- Official docs: <https://doc.mispay.co>
- When reporting issues, include the `x-trace-id` response header if you captured it.
