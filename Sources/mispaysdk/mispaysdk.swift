import Foundation
import UIKit

public class MISPaySDK {
    
    private var checkoutMessage: String?
    var checkoutViewController: CheckoutWebViewController?
    
    public init(urlString:String,onMessageReceived: @escaping (String) -> Void) {
       
        guard let url = URL(string: urlString) else {
            print("Web Checkout URL is invalid")
            return
        }
        
        checkoutViewController = CheckoutWebViewController(url: url,onMessageReceived: onMessageReceived)
        checkoutViewController?.modalPresentationStyle = .fullScreen
    }
    
    public func getCheckoutViewController()-> UIViewController{
        if let checkoutViewController = checkoutViewController {
            return checkoutViewController
        }else{
            return UIViewController()
        }
    }
}
