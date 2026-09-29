import SwiftUI
import WebKit
import AVFoundation

struct WebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        context.coordinator.webView = web
        web.load(URLRequest(url: URL(string: "https://tv.infralink.store")!))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            webView.load(action.request)
            return nil
        }
    }
}

struct SplashView: View {
    @State private var reveal: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

                Text("Infralink TV")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                    .mask(
                        GeometryReader { geo in
                            Rectangle()
                                .frame(width: geo.size.width * reveal, height: geo.size.height)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                    )
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                reveal = 1
            }
        }
    }
}

struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            WebView()
                .ignoresSafeArea()
                .background(Color.black)

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }
}

@main
struct SiteApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
