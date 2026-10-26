import UIKit
import CoreLocation
import mispaysdk

/// One-screen demo: initialize the SDK, start a sandbox checkout with the docs
/// sample order, and show every result (started / success / cancelled / failure).
final class DemoViewController: UIViewController {

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabel
        label.text = "Loading…"
        return label
    }()

    private let payButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Pay with MISPay"
        configuration.cornerStyle = .large
        let button = UIButton(configuration: configuration)
        button.isEnabled = false
        return button
    }()

    private let locationManager = CLLocationManager()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "MISPay Demo"
        view.backgroundColor = .systemBackground

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        payButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        view.addSubview(payButton)
        NSLayoutConstraint.activate([
            payButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            payButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            payButton.heightAnchor.constraint(equalToConstant: 54),
            payButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: payButton.bottomAnchor, constant: 32),
        ])

        payButton.addTarget(self, action: #selector(payTapped), for: .touchUpInside)

        if let creds = DemoCredentials.load() {
            MISPay.initialize(appId: creds.appId, appSecret: creds.appSecret, environment: .sandbox)
            statusLabel.text = "Sandbox ready — tap Pay to start a checkout."
            payButton.isEnabled = true
        } else {
            statusLabel.text = """
                Credentials missing.
                Create DemoApp/Sources/Credentials.local.plist with
                MISPAY_APP_ID and MISPAY_APP_SECRET from the MIS Pay team.
                """
        }

        // The checkout pages may use geolocation.
        locationManager.requestWhenInUseAuthorization()
    }

    @objc private func payTapped() {
        MISPayLog.info("Pay tapped — starting checkout flow", category: .demo)
        statusLabel.text = "Starting checkout…\n(GET /token → decrypt → POST /start-checkout)"
        payButton.isEnabled = false

        MISPay.startCheckout(
            from: self,
            request: DemoSampleOrder.make(),
            onCheckoutStarted: { [weak self] _, trackId in
                MISPayLog.info("checkout opened — trackId \(trackId)", category: .demo)
                self?.statusLabel.text = "Checkout opened.\ntrackId: \(trackId)"
            }
        ) { [weak self] result in
            guard let self = self else { return }
            self.payButton.isEnabled = true
            switch result {
            case .success(let token):
                let prefix = token.map { String($0.prefix(24)) } ?? "nil"
                MISPayLog.info("result: SUCCESS — token \(MISPayLog.redact(token))", category: .demo)
                self.statusLabel.text = "SUCCESS ✔\ntoken prefix: \(prefix)…\n(verify server-side)"
            case .cancelled:
                MISPayLog.info("result: CANCELLED — customer left the checkout", category: .demo)
                self.statusLabel.text = "CANCELLED — customer left the checkout."
            case .failure(let error):
                let meCode = error.meCode.map { " [\($0)]" } ?? ""
                MISPayLog.error("result: FAILURE\(meCode) \(error.localizedDescription)", category: .demo)
                self.statusLabel.text = "ERROR\(meCode)\n\(error.localizedDescription)"
            }
        }
    }
}

/// The sample order from the MIS Pay API documentation (unique orderId per run).
enum DemoSampleOrder {

    static func make() -> CheckoutRequest {
        CheckoutRequest(
            orderId: "DEMO-IOS-\(Int(Date().timeIntervalSince1970))",
            totalPrice: "215",
            shippingAmount: "0",
            vat: "15",
            // totalPrice + shippingAmount + vat - discount.amount = 215+0+15-30 = 200.
            // The API validates this formula and rejects mismatches with ME18.
            purchaseAmount: "200",
            purchaseCurrency: "SAR",
            lang: "en",
            invoiceId: "1234567890",
            discount: Discount(percentage: "15", amount: "30", voucherName: "MIS-30"),
            customerDetails: CustomerDetails(
                mobileNumber: "+966520006780",
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
            ),
            // Required for merchant accounts configured with a Dynamic callback URL.
            callbackUri: "https://example.com/mispay-callback"
        )
    }
}
