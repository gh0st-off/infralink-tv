import SwiftUI
import WebKit
import AVFoundation
import Security

// MARK: - Trousseau (Keychain)

enum CredStore {
    static let service = "infralink.tv.credentials"

    static func save(host: String, user: String, pass: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["u": user, "p": pass]) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(host: String) -> (user: String, pass: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let u = obj["u"], let p = obj["p"] else { return nil }
        return (u, p)
    }
}

// MARK: - Script injecté dans les pages

let credentialScript = #"""
(function(){
  if (window.__ilAuto) return; window.__ilAuto = true;
  var pending = null, lastSent = '', observing = false;

  function visible(e){ return e && e.offsetParent !== null; }
  function pwField(){
    var l = document.querySelectorAll('input[type="password"]');
    for (var i=0;i<l.length;i++){ if (visible(l[i])) return l[i]; }
    return null;
  }
  function userField(pw){
    var all = Array.prototype.slice.call(document.querySelectorAll('input'));
    var idx = all.indexOf(pw);
    for (var i=idx-1;i>=0;i--){
      var t = (all[i].type || 'text').toLowerCase();
      if (['text','email','tel'].indexOf(t) >= 0 && visible(all[i])) return all[i];
    }
    return null;
  }
  function setVal(el, v){
    var s = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
    s.call(el, v);
    el.dispatchEvent(new Event('input',{bubbles:true}));
    el.dispatchEvent(new Event('change',{bubbles:true}));
  }
  function tryFill(){
    if (!pending) return;
    var pw = pwField(); if (!pw) return;
    var u = userField(pw);
    if (u && !u.value) setVal(u, pending.u);
    if (!pw.value) setVal(pw, pending.p);
    pending = null;
  }
  window.__ilFill = function(u, p){
    pending = {u:u, p:p};
    tryFill();
    if (!observing){
      observing = true;
      new MutationObserver(tryFill).observe(document.documentElement,{childList:true,subtree:true});
    }
    setTimeout(function(){ pending = null; }, 60000);
  };

  function send(){
    var pw = pwField(); if (!pw || !pw.value) return;
    var u = userField(pw); var uv = u ? u.value : '';
    var key = uv + '|' + pw.value;
    if (key === lastSent) return;
    lastSent = key;
    window.webkit.messageHandlers.cred.postMessage({u:uv, p:pw.value});
  }
  document.addEventListener('submit', send, true);
  document.addEventListener('keydown', function(e){ if (e.key === 'Enter') send(); }, true);
  document.addEventListener('click', function(e){
    var t = e.target.closest && e.target.closest('button:not([type=button]),input[type=submit]');
    if (t) send();
  }, true);
})();
"""#

// MARK: - WebView

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

        let script = WKUserScript(source: credentialScript,
                                  injectionTime: .atDocumentEnd,
                                  forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
        config.userContentController.add(context.coordinator, name: "cred")

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

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?

        // Autorise toutes les navigations
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }

        // Accepte les certificats invalides
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

        // target="_blank" / window.open : même vue
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            webView.load(action.request)
            return nil
        }

        // Remplissage automatique quand la page est chargée
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let host = webView.url?.host,
                  let cred = CredStore.load(host: host),
                  let data = try? JSONSerialization.data(withJSONObject: [cred.user, cred.pass]),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("(function(a){ if(window.__ilFill) window.__ilFill(a[0],a[1]); })(\(json));")
        }

        // Réception d'un identifiant saisi par l'utilisateur
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "cred",
                  let body = message.body as? [String: String],
                  let user = body["u"], let pass = body["p"],
                  let host = webView?.url?.host else { return }

            if let saved = CredStore.load(host: host), saved.user == user, saved.pass == pass { return }

            let isUpdate = CredStore.load(host: host) != nil
            let alert = UIAlertController(
                title: isUpdate ? "Mettre à jour le mot de passe ?" : "Enregistrer le mot de passe ?",
                message: user.isEmpty ? host : "\(user) sur \(host)",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Pas maintenant", style: .cancel))
            alert.addAction(UIAlertAction(title: isUpdate ? "Mettre à jour" : "Enregistrer", style: .default) { _ in
                CredStore.save(host: host, user: user, pass: pass)
            })
            Self.topController()?.present(alert, animated: true)
        }

        static func topController() -> UIViewController? {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
            var top = root
            while let presented = top.presentedViewController { top = presented }
            return top
        }
    }
}

// MARK: - Écran de démarrage

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
