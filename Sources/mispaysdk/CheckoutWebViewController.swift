#if canImport(UIKit)
import UIKit
import WebKit

/// Hosts the MIS Pay checkout pages in a WKWebView.
///
/// Delivery modes (chosen by the initializer used):
///  - typed (`init(checkoutURL:completion:)`): `MISPayResult` — `.success` when the
///    page posts its final message, `.cancelled` on close/back, `.failure` when the
///    checkout document fails to load;
///  - legacy (`init(url:onMessageReceived:)`): raw message string only, behaviour
///    unchanged from SDK 1.x (no cancel/error delivery).
///
/// Bridge: the MIS Pay pages call
/// `window.webkit.messageHandlers.messageHandler.postMessage(body)` — the same
/// mechanism the original SDK used in production. Exactly one result is delivered
/// per presentation, and the static delivery slot is released immediately after.
public final class CheckoutWebViewController: UIViewController {

    // MARK: - Delivery slots (static, one checkout at a time)

    /// Typed `MISPay.startCheckout` completion slot.
    static var activeCompletion: ((MISPayResult) -> Void)?

    /// Legacy raw-message slot.
    static var legacyMessageHandler: ((String) -> Void)?

    private enum Constants {
        enum JavaScript {
            static let messageHandlerName = "messageHandler"
        }
        static let headerHeight: CGFloat = 44
    }

    // MARK: - State

    private let checkoutURL: URL
    private let typedCompletion: ((MISPayResult) -> Void)?
    private let legacyHandler: ((String) -> Void)?
    private var resultDelivered = false

    private lazy var webView: WKWebView = {
        let contentController = WKUserContentController()
        contentController.add(self, name: Constants.JavaScript.messageHandlerName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        // Parity with the Android SDK's WebView settings. DOM storage and the
        // SQL database have no equivalent here: WKWebView always provides
        // localStorage/sessionStorage via the default persistent data store,
        // so those Android flags map to "leave defaults as-is". JavaScript
        // opening windows DOES have a switch, and it defaults to false —
        // enable it so window.open()/target=_blank reach the UI delegate
        // (see the WKUIDelegate extension, the setSupportMultipleWindows
        // equivalent that keeps popups such as 3DS challenges inside the
        // checkout flow instead of silently dropping them).
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Disable zoom in/out (preserved from the original SDK).
        let source: String = "var meta = document.createElement('meta');"
            + "meta.name = 'viewport';"
            + "meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';"
            + "var head = document.getElementsByTagName('head')[0];"
            + "head.appendChild(meta);"
        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(script)

        return WKWebView(frame: .zero, configuration: configuration)
    }()

    // MARK: - Init (typed)

    init(checkoutURL: URL, completion: @escaping (MISPayResult) -> Void) {
        self.checkoutURL = checkoutURL
        self.typedCompletion = completion
        self.legacyHandler = nil
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    // MARK: - Init (legacy, SDK 1.x shape)

    init(url: URL, onMessageReceived: @escaping (String) -> Void) {
        self.checkoutURL = url
        self.typedCompletion = nil
        self.legacyHandler = onMessageReceived
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // The original SDK never removed the script handler, leaking the controller
        // through the content controller's strong reference.
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: Constants.JavaScript.messageHandlerName)
        Self.clearDeliverySlots()
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildHeader()
        embedWebView()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        MISPayLog.info(
            "loading checkout page \(checkoutURL.scheme ?? "")://\(checkoutURL.host ?? "?")\(checkoutURL.path)" +
                (checkoutURL.query.map { "?…(\($0.count) chars redacted)" } ?? ""),
            category: .webview
        )
        webView.load(URLRequest(url: checkoutURL))
    }

    // MARK: - Result delivery (exactly once)

    private func deliverResult(_ result: MISPayResult) {
        guard !resultDelivered else { return }
        resultDelivered = true
        defer { Self.clearDeliverySlots() }
        if let typedCompletion = typedCompletion {
            typedCompletion(result)
        } else if let legacyHandler = legacyHandler, case .success(let token) = result {
            legacyHandler(token ?? "")
        }
    }

    static func clearDeliverySlots() {
        activeCompletion = nil
        legacyMessageHandler = nil
    }

    // MARK: - UI

    private lazy var backButton: UIButton = {
        let button = UIButton(type: .system)
        let image = UIImage(systemName: "chevron.left")
        button.setImage(image, for: .normal)
        button.accessibilityLabel = "Back"
        button.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Close", for: .normal)
        button.accessibilityLabel = "Close checkout"
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return button
    }()

    private func buildHeader() {
        let header = UIView()
        header.backgroundColor = .systemBackground
        header.translatesAutoresizingMaskIntoConstraints = false

        backButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(backButton)
        header.addSubview(closeButton)

        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Constants.headerHeight),

            backButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backButton.heightAnchor.constraint(equalToConstant: Constants.headerHeight),

            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.heightAnchor.constraint(equalToConstant: Constants.headerHeight),
        ])
        webViewTopConstraint = webView.topAnchor.constraint(equalTo: header.bottomAnchor)
    }

    private var webViewTopConstraint: NSLayoutConstraint?

    private func embedWebView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ].compactMap { $0 } + [webViewTopConstraint].compactMap { $0 })
    }

    // MARK: - Actions

    @objc private func backTapped() {
        if webView.canGoBack {
            MISPayLog.info("back tapped — navigating back in checkout history", category: .webview)
            webView.goBack()
        } else {
            MISPayLog.info("back tapped on first page — delivering .cancelled", category: .webview)
            deliverResult(.cancelled)
            dismiss(animated: true)
        }
    }

    @objc private func closeTapped() {
        MISPayLog.info("close tapped — delivering .cancelled", category: .webview)
        deliverResult(.cancelled)
        dismiss(animated: true)
    }
}

// MARK: - WKScriptMessageHandler (checkout page bridge)

extension CheckoutWebViewController: WKScriptMessageHandler {

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Constants.JavaScript.messageHandlerName,
              let body = message.body as? String else { return }
        MISPayLog.info(
            "checkout message received — \(MISPayLog.redact(body)), delivering .success",
            category: .webview
        )
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.deliverResult(.success(token: body))
            self.dismiss(animated: true)
        }
    }
}

// MARK: - WKUIDelegate (setSupportMultipleWindows equivalent — popup handling)

extension CheckoutWebViewController: WKUIDelegate {

    /// New-window requests (window.open, target="_blank" — e.g. a 3DS challenge)
    /// are loaded in the same checkout WebView. Returning nil tells WebKit not to
    /// create a separate window, which keeps the flow inside this controller and
    /// the existing back-button/result plumbing intact.
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            MISPayLog.info(
                "new-window request — loading in checkout WebView: \(navigationAction.request.url?.host ?? "?")",
                category: .webview
            )
            webView.load(navigationAction.request)
        }
        return nil
    }

    /// A window we returned nil for may still be asked to close itself; treat it
    /// as a no-op so the checkout screen stays up.
    public func webViewDidClose(_ webView: WKWebView) {}
}

// MARK: - WKNavigationDelegate (load-failure fallback + back-button state)

extension CheckoutWebViewController: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Main-document load failed (offline, DNS, TLS…): surface Error instead of
        // leaving a blank screen.
        MISPayLog.error("checkout page FAILED (provisional): \(error.localizedDescription) \((error as NSError))", category: .webview)
        deliverResult(.failure(MISPayError(message: "Checkout page failed to load: \(error.localizedDescription)")))
        dismiss(animated: true)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MISPayLog.error("checkout page FAILED: \(error.localizedDescription) \((error as NSError))", category: .webview)
        deliverResult(.failure(MISPayError(message: "Checkout page failed to load: \(error.localizedDescription)")))
        dismiss(animated: true)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MISPayLog.info(
            "checkout page loaded — \(webView.url?.host ?? "?")\(webView.url?.path ?? "")",
            category: .webview
        )
        backButton.isHidden = !webView.canGoBack
    }
}
#endif
