import Foundation

/// Outcome of a checkout flow started with `MISPay.startCheckout`.
public enum MISPayResult: Sendable {
    /// The customer finished the checkout on the MIS Pay pages. `token` is the value
    /// delivered by the checkout page; per the MIS Pay documentation it encodes the
    /// success or failure of the payment and must be verified server-side.
    case success(token: String?)
    /// The customer left the checkout before completing it (close/back).
    case cancelled
    /// The flow failed before or during the checkout pages
    /// (network, API, crypto or validation).
    case failure(MISPayError)
}
