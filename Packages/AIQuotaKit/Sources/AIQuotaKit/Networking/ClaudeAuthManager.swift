import Foundation
import WebKit
import AppKit
import os

// MARK: - ClaudeAuthManager

/// Cookie-based authentication for claude.ai.
///
/// Flow:
///   1. Check default WKWebsiteDataStore for existing lastActiveOrg / sessionKey cookie
///   2. If found → sync cookies to HTTPCookieStorage.shared → mark authenticated
///   3. If not found → present claude.ai in a WKWebView login window
///   4. After login, detect auth via cookie polling (claude.ai is a SPA — a single
///      didFinish fires for /login; subsequent navigation is client-side only)

@MainActor
public final class ClaudeAuthManager: NSObject, ObservableObject {
    @Published public var isAuthenticated = false

    static let loginCookies = ["lastActiveOrg", "sessionKey", "routingHint"]

    /// UserDefaults key set synchronously on sign-out. Blocks silentSignInIfPossible
    /// from treating stale WKWebView cookies as a valid session after an explicit
    /// sign-out. Cleared only after the user completes an explicit login flow.
    private static let explicitlySignedOutKey = "claude.explicitlySignedOut"

    private let logger = Logger(subsystem: "ai.quota", category: "claude-auth")

    private var loginWindowController: ClaudeLoginWindowController?

    public override init() {
        super.init()
        loadAuthFromKeychain()
    }

    // MARK: - Sign In

    public func signIn() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let controller = ClaudeLoginWindowController { [weak self] result in
                Task { @MainActor [weak self] in
                    self?.loginWindowController = nil
                    switch result {
                    case .success:
                        KeychainStore.save("true", forKey: "claudeAuthenticated")
                        UserDefaults.standard.removeObject(forKey: Self.explicitlySignedOutKey)
                        self?.isAuthenticated = true
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            self.loginWindowController = controller
            controller.show()
        }
    }

    // MARK: - Silent Re-Auth

    /// Checks the WKWebView cookie store for existing Claude session cookies without showing any UI.
    /// If valid cookies are found, syncs them and marks as authenticated.
    /// Pass `forceRecheck: true` to re-verify cookies even when already marked authenticated
    /// (used during refresh to recover from stale URLSession cookies without a UI flash).
    @discardableResult
    public func silentSignInIfPossible(forceRecheck: Bool = false) async -> Bool {
        guard !isAuthenticated || forceRecheck else { return true }
        // After an explicit sign-out, block silent re-auth from treating stale
        // WKWebView cookies as valid. forceRecheck (session recovery) still passes.
        guard forceRecheck || !UserDefaults.standard.bool(forKey: Self.explicitlySignedOutKey) else {
            return false
        }
        return await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { continuation.resume(returning: false); return }
                let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
                guard claudeCookies.contains(where: { Self.loginCookies.contains($0.name) }) else {
                    continuation.resume(returning: false)
                    return
                }
                for cookie in claudeCookies { HTTPCookieStorage.shared.setCookie(cookie) }
                Task { @MainActor [weak self] in
                    guard let self else { continuation.resume(returning: false); return }
                    KeychainStore.save("true", forKey: "claudeAuthenticated")
                    UserDefaults.standard.removeObject(forKey: Self.explicitlySignedOutKey)
                    self.isAuthenticated = true
                    self.logger.info("[ClaudeAuth] silent re-auth succeeded")
                    continuation.resume(returning: true)
                }
            }
        }
    }

    // MARK: - Sign Out

    /// Clears all auth state and waits for WKWebView cookie deletion to complete
    /// before returning. Callers must await this to prevent silentSignInIfPossible
    /// from racing and finding stale cookies immediately after sign-out.
    public func signOut() async {
        isAuthenticated = false
        KeychainStore.delete(forKey: "claudeAuthenticated")
        // Set synchronously — blocks silentSignInIfPossible immediately, even
        // before the async WKWebView deletion completes.
        UserDefaults.standard.set(true, forKey: Self.explicitlySignedOutKey)
        // Delete from HTTPCookieStorage synchronously — no race possible.
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.domain.contains("claude.ai") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        // Await WKWebView cookie deletion so callers don't race with it.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
                guard !claudeCookies.isEmpty else { cont.resume(); return }
                let group = DispatchGroup()
                for cookie in claudeCookies {
                    group.enter()
                    WKWebsiteDataStore.default().httpCookieStore.delete(cookie) { group.leave() }
                }
                group.notify(queue: .main) { cont.resume() }
            }
        }
    }

    // MARK: - Cookie Sync

    public func syncCookies() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                for cookie in cookies where cookie.domain.contains("claude.ai") {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Keychain bootstrap

    private func loadAuthFromKeychain() {
        isAuthenticated = KeychainStore.load(forKey: "claudeAuthenticated") != nil
    }
}

// MARK: - ClaudeLoginWindowController

@MainActor
final class ClaudeLoginWindowController: NSObject {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var cookieObserver: ClaudeCookieObserver?
    private let onComplete: (Result<Void, Error>) -> Void
    private var hasCompleted = false
    private var pollTimer: Timer?

    private static var loginCookies: [String] { ClaudeAuthManager.loginCookies }

    private let logger = Logger(subsystem: "ai.quota", category: "claude-login")

    init(onComplete: @escaping (Result<Void, Error>) -> Void) {
        self.onComplete = onComplete
    }

    func show() {
        // Skip the cookie pre-check here — silentSignInIfPossible() already ran
        // before signIn() was called, so if we've reached this point the user
        // genuinely needs to log in. Going straight to showWindow() avoids the
        // async getAllCookies delay that caused the login window to appear late.
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        showWindow(config: config)
    }

    private func showWindow(config: WKWebViewConfiguration) {
        let webView = WKWebView(
            frame: .init(x: 0, y: 0, width: 520, height: 680),
            configuration: config
        )
        webView.navigationDelegate = self
        self.webView = webView

        // CookieObserver catches cookies set by server responses
        let observer = ClaudeCookieObserver { [weak self] in
            Task { @MainActor [weak self] in self?.complete(with: .success(())) }
        }
        config.websiteDataStore.httpCookieStore.add(observer)
        self.cookieObserver = observer

        let win = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Sign in to Claude"
        win.contentView = webView
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.delegate = self
        self.window = win

        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Cookie polling (handles SPA client-side navigation)
    // claude.ai only produces one didFinish for /login; subsequent auth redirects
    // are client-side. Poll every second until login cookies appear.

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollCookies() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollCookies() {
        guard !hasCompleted, let wv = webView else { stopPolling(); return }

        // Fast path: check JS-readable cookies (lastActiveOrg is not HttpOnly)
        wv.evaluateJavaScript("document.cookie") { [weak self] result, _ in
            guard let self, !self.hasCompleted else { return }

            if let jsCookies = result as? String,
               Self.loginCookies.contains(where: { jsCookies.contains("\($0)=") }) {
                self.logger.info("[ClaudeAuth] found login cookie in JS ✓")
                wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    for cookie in cookies where cookie.domain.contains("claude.ai") {
                        HTTPCookieStorage.shared.setCookie(cookie)
                    }
                    Task { @MainActor [weak self] in self?.complete(with: .success(())) }
                }
                return
            }

            // Also check WK store (catches HttpOnly cookies like sessionKey)
            wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.hasCompleted else { return }
                let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
                self.logger.info("[ClaudeAuth] polling cookies: \(claudeCookies.map(\.name))")

                if claudeCookies.contains(where: { Self.loginCookies.contains($0.name) }) {
                    for cookie in claudeCookies { HTTPCookieStorage.shared.setCookie(cookie) }
                    Task { @MainActor [weak self] in self?.complete(with: .success(())) }
                }
            }
        }
    }

    // MARK: -

    private func complete(with result: Result<Void, Error>) {
        guard !hasCompleted else { return }
        hasCompleted = true
        stopPolling()
        window?.close()
        window = nil
        webView = nil
        cookieObserver = nil
        onComplete(result)
    }
}

// MARK: - WKNavigationDelegate

@MainActor
extension ClaudeLoginWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        logger.info("[ClaudeAuth] didFinish: \(url.path)")

        // Start polling after any page load — SPA navigation won't trigger
        // further didFinish events, so we poll until login cookies appear.
        startPolling()
    }
}

@MainActor
extension ClaudeLoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard !hasCompleted else { return }
        complete(with: .failure(NetworkError.notAuthenticated))
    }
}

// MARK: - Cookie Observer

private final class ClaudeCookieObserver: NSObject, WKHTTPCookieStoreObserver, @unchecked Sendable {
    private let onSessionFound: @Sendable () -> Void
    private var hasFound = false
    private static var loginCookies: [String] { ClaudeAuthManager.loginCookies }

    init(onSessionFound: @Sendable @escaping () -> Void) {
        self.onSessionFound = onSessionFound
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard !hasFound else { return }
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self, !self.hasFound else { return }
            let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
            if claudeCookies.contains(where: { Self.loginCookies.contains($0.name) }) {
                self.hasFound = true
                for cookie in claudeCookies { HTTPCookieStorage.shared.setCookie(cookie) }
                self.onSessionFound()
            }
        }
    }
}
