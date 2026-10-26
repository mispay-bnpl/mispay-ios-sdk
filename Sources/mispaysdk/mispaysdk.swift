#if canImport(UIKit)
import Foundation
import UIKit

/// Legacy SDK 1.x entry point: builds a raw-URL checkout view controller and
/// delivers the final page message as a plain string. No /token or /start-checkout
/// calls are made; no cancelled/error delivery — behaviour unchanged from SDK 1.x.
///
/// - Deprecated: use `MISPay.initialize` + `MISPay.startCheckout(from:request:…)`
///   which perform the documented token → start-checkout → WebView flow with
///   typed results.
@available(iOS, deprecated: 13.0, message: "Use MISPay.startCheckout(from:request:completion:) instead")
public class MISPaySDK {

    private var checkoutMessage: String?
    private var checkoutViewController: CheckoutWebViewController?

    public init(urlString: String, onMessageReceived: @escaping (String) -> Void) {
        guard let url = URL(string: urlString) else {
            print("Web Checkout URL is invalid")
            return
        }
        checkoutViewController = CheckoutWebViewController(url: url, onMessageReceived: onMessageReceived)
        checkoutViewController?.modalPresentationStyle = .fullScreen
        checkoutMessage = urlString
    }

    public func getCheckoutViewController() -> UIViewController {
        if let checkoutViewController = checkoutViewController {
            return checkoutViewController
        } else {
            return UIViewController()
        }
    }
}
#endif
