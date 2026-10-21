import Observation
import SwiftUI
import WebKit
import MobileAccessCore

/// Signs in with an isolated website store. Only after the OAuth exchange and
/// usage check succeed are Claude cookies copied to the Enterprise detail store.
@MainActor @Observable
final class ClaudeAuthorizationBrowser: NSObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let webView: WKWebView
    private(set) var popup: WKWebView?
    private(set) var navigationFailed = false
    private(set) var capturedCode = false
    private let challenge: ClaudeChallenge
    private let onAuthorization: (String, ClaudeAuthorizationBrowser) -> Void
    private let websiteDataStore: WKWebsiteDataStore
    private var cancelled = false
    private var started = false

    init(challenge: ClaudeChallenge, onAuthorization: @escaping (String, ClaudeAuthorizationBrowser) -> Void) {
        self.challenge = challenge
        self.onAuthorization = onAuthorization
        let configuration = WKWebViewConfiguration()
        websiteDataStore = .nonPersistent()
        configuration.websiteDataStore = websiteDataStore
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func start() {
        guard !started, !cancelled else { return }
        started = true
        webView.load(URLRequest(url: challenge.authorizationURL))
    }

    func stop() {
        cancelled = true
        webView.stopLoading()
        popup?.stopLoading()
        popup = nil
    }

    /// Keep the existing Enterprise detail session until the OAuth account and
    /// this candidate website session report the same organization.
    func commitWebsiteSession(expectedOrganizationID: String?, into destination: WKWebsiteDataStore) async {
        guard !cancelled, capturedCode, let expectedOrganizationID,
              UUID(uuidString: expectedOrganizationID) != nil else { return }
        let candidate = ClaudeWebDetailsSession(websiteDataStore: websiteDataStore)
        candidate.start(organization: .verified(expectedOrganizationID))
        var verified = false
        for _ in 0..<20 {
            if cancelled { candidate.invalidate(); return }
            if candidate.state == .ready { verified = true; break }
            if candidate.state == .accountMismatch || candidate.state == .signInRequired
                || candidate.state == .unavailable { break }
            try? await Task.sleep(for: .seconds(1))
        }
        candidate.invalidate()
        guard verified, !cancelled else { return }
        let source = websiteDataStore.httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            source.getAllCookies { continuation.resume(returning: $0) }
        }.filter(Self.isClaudeCookie)
        guard !cancelled, !cookies.isEmpty else { return }
        let target = destination.httpCookieStore
        let old = await withCheckedContinuation { continuation in
            target.getAllCookies { continuation.resume(returning: $0) }
        }
        guard !cancelled else { return }
        for cookie in old where Self.isClaudeCookie(cookie) {
            await withCheckedContinuation { continuation in
                target.delete(cookie) { continuation.resume() }
            }
        }
        for cookie in cookies {
            await withCheckedContinuation { continuation in
                target.setCookie(cookie) { continuation.resume() }
            }
        }
        if cancelled {
            for cookie in cookies {
                await withCheckedContinuation { continuation in
                    target.delete(cookie) { continuation.resume() }
                }
            }
            for cookie in old where Self.isClaudeCookie(cookie) {
                await withCheckedContinuation { continuation in
                    target.setCookie(cookie) { continuation.resume() }
                }
            }
        }
    }

    private static func isClaudeCookie(_ cookie: HTTPCookie) -> Bool {
        cookie.domain == "claude.ai" || cookie.domain.hasSuffix(".claude.ai")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              url.scheme == "https", url.host == "console.anthropic.com",
              url.path == "/oauth/code/callback" else {
            return .allow
        }
        // Never forward a callback from another attempt or expose it in a log.
        guard !cancelled, !capturedCode,
              let code = try? challenge.authorizationCode(from: url) else {
            return .allow
        }
        capturedCode = true
        popup?.stopLoading()
        popup = nil
        onAuthorization(code, self)
        return .cancel
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { navigationFailed = true }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.navigationDelegate = self
        child.uiDelegate = self
        popup = child
        return child
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === popup { popup = nil }
    }
}

struct ClaudeAuthorizationBrowserView: View {
    let session: ClaudeAuthorizationBrowser
    let useSafari: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showPopup = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if session.capturedCode {
                    ProgressView("Connecting Claude…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ClaudeWebSurface(webView: session.webView)
                }
                if session.navigationFailed {
                    HStack {
                        Text("Claude sign-in couldn't load here.")
                        Spacer()
                        Button("Use Safari", action: useSafari)
                    }
                    .font(.footnote)
                    .padding(12)
                }
            }
            .navigationTitle("Sign in with Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.disabled(session.capturedCode)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use Safari", action: useSafari).disabled(session.capturedCode)
                }
            }
            .sheet(isPresented: $showPopup, onDismiss: {
                if let popup = session.popup { session.webViewDidClose(popup) }
            }) {
                if let popup = session.popup {
                    NavigationStack {
                        ClaudeWebSurface(webView: popup)
                            .navigationTitle("Continue sign-in")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                                Button("Close") { session.webViewDidClose(popup) }
                            } }
                    }
                }
            }
        }
        .onChange(of: session.popup, initial: true) { _, popup in showPopup = popup != nil }
        .onAppear { session.start() }
        .onDisappear { session.stop() }
    }
}
