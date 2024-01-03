//
//  CheckoutWebViewController.swift
//  MIS Pay Web Integration
//
//  Created by Finbyte GmbH on 12/11/23.
//

import UIKit
import WebKit

final class CheckoutWebViewController: UIViewController {
    
    private enum Constants {
        enum JavaScript {
            static let name = "messageHandler"
        }
    }
    
    private let url: URL
    private let onMessageReceived: (String) -> Void
    
    private lazy var webView: WKWebView = {
        let contentController = WKUserContentController()
        contentController.add(self, name: Constants.JavaScript.name)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        
        // Disable zoom in/out
        let source: String = "var meta = document.createElement('meta');"
            + "meta.name = 'viewport';"
            + "meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';"
            + "var head = document.getElementsByTagName('head')[0];"
            + "head.appendChild(meta);"
        let script: WKUserScript = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(script)

        return WKWebView(frame: view.frame, configuration: configuration)
    }()
    
    init(url: URL, onMessageReceived: @escaping (String) -> Void) {
        self.url = url
        self.onMessageReceived = onMessageReceived
        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        let constraints = [
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]
        NSLayoutConstraint.activate(constraints)
        
        let urlRequest = URLRequest(url: url)
        webView.load(urlRequest)
    }

}

extension CheckoutWebViewController: WKScriptMessageHandler {
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == Constants.JavaScript.name, let body = message.body as? String {
            onMessageReceived(body)
        }
    }
    
}
