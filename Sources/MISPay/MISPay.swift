import UIKit

public final class MISPay {
    
    public static func checkout(
        viewController: UIViewController,
        url: URL,
        onMessageReceived: @escaping (String) -> Void
    ) {
        let checkoutViewController = CheckoutWebViewController(url: url, onMessageReceived: onMessageReceived)
        checkoutViewController.modalPresentationStyle = .fullScreen
        viewController.present(checkoutViewController, animated: true)
    }
    
}
