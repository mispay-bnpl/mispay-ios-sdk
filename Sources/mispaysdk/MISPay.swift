#if canImport(UIKit)
import UIKit

/// MIS Pay checkout SDK entry point.
///
/// Typical usage:
/// ```swift
/// MISPay.initialize(appId: appId, appSecret: secret, environment: .sandbox)
/// MISPay.startCheckout(from: self, request: request) { result in
///     switch result {
///     case .success(let token): verifyTokenServerSide(token)
///     case .cancelled:          handleCancellation()
///     case .failure(let error): showError(error)
///     }
/// }
/// ```
///
/// Delivery guarantees:
///  - the completion is invoked on the **main thread**, exactly **once** per call —
///    `.success` when the customer finishes, `.cancelled` on close/back,
///    `.failure` for every other failure (validation, network, API, decryption,
///    page load);
///  - only **one checkout can be active at a time**; a second call while one is in
///    flight fails fast with `.failure`;
///  - if the host process is killed while the customer is on the MIS Pay pages, no
///    in-app result can be delivered — the authoritative fallbacks are your
///    `callbackUri` webhook and `GET /track-checkout/{trackId}` polling.
public enum MISPay {

    // MARK: - State

    nonisolated(unsafe) private static var config: MISPayConfig?
    nonisolated(unsafe) private static var api: MISPayApi?
    nonisolated(unsafe) private static var tokenManager: TokenManager?

    private static let meInvalidToken = "ME10"
    private static let meSessionExpired = "ME11"

    // MARK: - Initialize

    /// Configures the SDK with the credentials provided by the MIS Pay Technical
    /// Team. Call once during app launch, before `startCheckout(from:…)`. Calling
    /// it again replaces the configuration and drops any cached token.
    public static func initialize(appId: String, appSecret: String, environment: MISPayEnvironment) {
        precondition(!appId.trimmingCharacters(in: .whitespaces).isEmpty, "appId must not be blank")
        precondition(!appSecret.trimmingCharacters(in: .whitespaces).isEmpty, "appSecret must not be blank")
        let environmentApi = MISPayApi(baseUrl: environment.baseUrl)
        config = MISPayConfig(appId: appId, appSecret: appSecret, environment: environment)
        api = environmentApi
        tokenManager = TokenManager(dataSource: environmentApi)
    }

    // MARK: - Start checkout

    /// Runs the full checkout flow:
    ///  1. fetch + AES-256-GCM decrypt the /token JWT (cached ~8 h);
    ///  2. POST the order to /start-checkout (one automatic retry on ME10/ME11);
    ///  3. present the returned checkout URL in the MIS Pay WebView;
    ///  4. deliver `.success(token)` when the page posts its final message,
    ///     `.cancelled` when the customer closes/backs out, or `.failure` when any
    ///     step fails.
    ///
    /// `onCheckoutStarted` (url, trackId) and `completion` are invoked on the main
    /// thread; exactly one terminal result is delivered per call. Validation
    /// failures of `request` are delivered as `.failure` (never thrown).
    public static func startCheckout(
        from presenter: UIViewController,
        request: CheckoutRequest,
        onCheckoutStarted: ((String, String) -> Void)? = nil,
        completion: @escaping (MISPayResult) -> Void
    ) {
        let onMain: (MISPayResult) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }

        guard let activeConfig = config, let activeApi = api, let manager = tokenManager else {
            MISPayLog.error("checkout aborted — MISPay.initialize(appId:appSecret:environment:) was not called", category: .flow)
            onMain(.failure(MISPayError(
                message: "Call MISPay.initialize(appId:appSecret:environment:) before startCheckout()"
            )))
            return
        }

        do {
            try request.validate()
        } catch let error as MISPayError {
            MISPayLog.error("checkout aborted — request validation failed: \(error.localizedDescription)", category: .flow)
            onMain(.failure(error))
            return
        } catch {
            MISPayLog.error("checkout aborted — request validation failed: \(error.localizedDescription)", category: .flow)
            onMain(.failure(MISPayError(message: error.localizedDescription)))
            return
        }

        guard CheckoutWebViewController.activeCompletion == nil else {
            MISPayLog.error("checkout refused — another checkout is already in progress", category: .flow)
            onMain(.failure(MISPayError(
                message: "A checkout is already in progress. Wait for its result before starting another one."
            )))
            return
        }

        MISPayLog.info(
            "checkout start — orderId \(request.orderId), env \(activeConfig.environment.baseUrl)",
            category: .flow
        )
        DispatchQueue.global(qos: .userInitiated).async {
            runCheckout(config: activeConfig, api: activeApi, manager: manager, request: request) { outcome in
                DispatchQueue.main.async {
                    switch outcome {
                    case .started(let url, let trackId):
                        MISPayLog.info("checkout started — trackId \(trackId), url \(Self.loggable(url))", category: .flow)
                        guard let checkoutURL = URL(string: url) else {
                            MISPayLog.error("checkout URL invalid: \(String(url.prefix(80)))", category: .flow)
                            completion(.failure(MISPayError(
                                message: "Checkout URL returned by the API is invalid: \(String(url.prefix(80)))"
                            )))
                            return
                        }
                        guard presenter.presentedViewController == nil else {
                            MISPayLog.error("cannot present checkout — presenter already has a presented view controller", category: .flow)
                            completion(.failure(MISPayError(
                                message: "Cannot present the checkout: the presenting view controller " +
                                    "already has a presented view controller."
                            )))
                            return
                        }
                        CheckoutWebViewController.activeCompletion = completion
                        let controller = CheckoutWebViewController(checkoutURL: checkoutURL) { result in
                            completion(result)
                        }
                        presenter.present(controller, animated: true)
                        onCheckoutStarted?(url, trackId)

                    case .failed(let error):
                        MISPayLog.error("checkout failed — \(error.localizedDescription)", category: .flow)
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    /// URL with the query string redacted (checkout URLs can carry session parameters).
    private static func loggable(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              let host = url.host else {
            return String(urlString.prefix(60))
        }
        var description = "\(scheme)://\(host)\(url.path)"
        if let query = url.query, !query.isEmpty {
            description += "?…(\(query.count) chars redacted)"
        }
        return description
    }

    // MARK: - Flow

    private enum Outcome {
        case started(url: String, trackId: String)
        case failed(MISPayError)
    }

    private static func runCheckout(
        config: MISPayConfig,
        api: MISPayApi,
        manager: TokenManager,
        request: CheckoutRequest,
        completion: @escaping (Outcome) -> Void
    ) {
        attempt(config: config, api: api, manager: manager, request: request) { firstOutcome in
            if case .failed(let error) = firstOutcome,
               error.meCode == meInvalidToken || error.meCode == meSessionExpired {
                // Token rejected (ME10/ME11): drop cache and retry exactly once.
                MISPayLog.info(
                    "token rejected (\(error.meCode ?? "?")) — invalidating cache and retrying once",
                    category: .flow
                )
                manager.invalidate()
                attempt(config: config, api: api, manager: manager, request: request) { retryOutcome in
                    completion(retryOutcome)
                }
            } else {
                completion(firstOutcome)
            }
        }
    }

    private static func attempt(
        config: MISPayConfig,
        api: MISPayApi,
        manager: TokenManager,
        request: CheckoutRequest,
        completion: @escaping (Outcome) -> Void
    ) {
        manager.getValidToken(appId: config.appId, appSecret: config.appSecret) { tokenResult in
            switch tokenResult {
            case .failure(let error):
                completion(.failed(error))
            case .success(let decrypted):
                let body: Data
                do {
                    body = try request.jsonBody()
                } catch let error as MISPayError {
                    completion(.failed(error))
                    return
                } catch {
                    completion(.failed(MISPayError(message: error.localizedDescription)))
                    return
                }
                api.startCheckout(appId: config.appId, bearerToken: decrypted.token, body: body) { startResult in
                    switch startResult {
                    case .failure(let error):
                        completion(.failed(error))
                    case .success(let started):
                        completion(.started(url: started.url, trackId: started.trackId))
                    }
                }
            }
        }
    }
}
#endif
