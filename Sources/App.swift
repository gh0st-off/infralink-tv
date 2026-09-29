import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = web
        web.load(URLRequest(url: URL(string: "https://tv.infralink.store")!))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?

        func isAllowed(_ url: URL?) -> Bool {
            guard let host = url?.host else { return true }
            return host == "infralink.store" || host.hasSuffix(".infralink.store")
        }

        // Bloque uniquement la navigation de la page principale vers un autre site.
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let isMainFrame = action.targetFrame?.isMainFrame ?? true
            if isMainFrame && !isAllowed(action.request.url) {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        // Liens target="_blank" / window.open : ouverts dans la même vue si autorisés.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if isAllowed(action.request.url) {
                webView.load(action.request)
            }
            return nil
        }
    }
}

@main
struct SiteApp: App {
    var body: some Scene {
        WindowGroup { WebView().ignoresSafeArea() }
    }
}