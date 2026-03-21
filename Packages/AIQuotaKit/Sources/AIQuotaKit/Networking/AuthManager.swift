import Foundation
import WebKit
import AppKit
import os

// MARK: - Session API response
// GET https://chatgpt.com/api/auth/session → { "accessToken": "eyJ...", "expires": "..." }

private struct SessionResponse: Decodable {
    let accessToken: String
    let expires: String?
}

// MARK: - AuthManager

/// Authentication flow:
/// 1. Check WKWebView default store for existing __Secure-next-auth.session-token cookie
/// 2. If found → sync all chatgpt.com cookies to HTTPCookieStorage.shared, complete immediately
/// 3. If not found → show chatgpt.com in a WKWebView window, wait for user to log in
/// 4. Once session token captured → POST to /api/auth/session → Bearer JWT
/// 5. Cache JWT (~24h); re-fetch cheaply via /api/auth/session on expiry

@MainActor
public final class AuthManager: NSObject, ObservableObject {
    @Published public var isAuthenticated = false

    private let logger = Logger(subsystem: "ai.quota", category: "codex-auth")

    private let sessionEndpoint = URL(string: "https://chatgpt.com/api/auth/session")!
    private let loginURL = URL(string: "https://chatgpt.com")!

    // In-memory JWT cache
    private var cachedAccessToken: String?
    private var tokenExpiresAt: Date?

    // Strong reference — keeps LoginWindowController alive until auth completes
    private var loginWindowController: LoginWindowController?

    public override init() {
        super.init()
        Self.clearStateIfFreshInstall()
        loadSessionFromKeychain()
    }

    // MARK: - Fresh-install cleanup

    /// Keychain entries survive app uninstall on macOS, which causes "Not signed in"
    /// banners on reinstall when the session cookies are gone but the token remains.
    /// We use a sentinel key to detect a fresh install and wipe stale auth state.
    private static func clearStateIfFreshInstall() {
        let sentinel = "app.installedAt.v1"
        guard KeychainStore.load(forKey: sentinel) == nil else { return }
        // First launch after fresh install — clear everything
        KeychainStore.delete(forKey: "sessionToken")
        KeychainStore.delete(forKey: "claudeAuthenticated")
        SharedDefaults.clearUsage()
        SharedDefaults.clearClaudeUsage()
        KeychainStore.save("1", forKey: sentinel)
    }

    // MARK: - Access Token

    public var accessToken: String {
        get async throws {
            if let token = cachedAccessToken,
               let exp = tokenExpiresAt,
               exp.addingTimeInterval(-60) > .now {
                return token
            }
            guard KeychainStore.load(forKey: "sessionToken") != nil else {
                throw NetworkError.notAuthenticated
            }
            return try await refreshAccessToken()
        }
    }

    // MARK: - Sign In

    public func signIn() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Strong capture — controller must outlive this closure
            let controller = LoginWindowController(baseURL: loginURL) { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.loginWindowController = nil  // release after completion
                    switch result {
                    case .success(let sessionToken):
                        KeychainStore.save(sessionToken, forKey: "sessionToken")
                        do {
                            _ = try await self.refreshAccessToken()
                            self.isAuthenticated = true
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            // Hold strong reference so the controller isn't deallocated
            // before the async getAllCookies callback fires
            self.loginWindowController = controller
            controller.show()
        }
    }

    // MARK: - Silent Re-Auth

    /// Checks the WKWebView cookie store for an existing ChatGPT session without showing any UI.
    /// If a valid session cookie is found, syncs it and fetches a fresh JWT.
    @discardableResult
    public func silentSignInIfPossible() async -> Bool {
        guard !isAuthenticated else { return true }
        return await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { continuation.resume(returning: false); return }
                guard let sessionCookie = cookies.first(where: {
                    $0.name == "__Secure-next-auth.session-token" && $0.domain.contains("chatgpt.com")
                }) else {
                    continuation.resume(returning: false)
                    return
                }
                for cookie in cookies where
                    cookie.domain.contains("chatgpt.com") || cookie.domain.contains("openai.com") {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                KeychainStore.save(sessionCookie.value, forKey: "sessionToken")
                Task { @MainActor [weak self] in
                    guard let self else { continuation.resume(returning: false); return }
                    do {
                        _ = try await self.refreshAccessToken()
                        self.logger.info("[Auth] silent re-auth succeeded")
                        continuation.resume(returning: true)
                    } catch {
                        self.logger.info("[Auth] silent re-auth failed: \(error)")
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    // MARK: - Sign Out

    public func signOut() {
        cachedAccessToken = nil
        tokenExpiresAt = nil
        isAuthenticated = false
        KeychainStore.delete(forKey: "sessionToken")
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            for cookie in cookies where
                cookie.domain.contains("chatgpt.com") || cookie.domain.contains("openai.com") {
                WKWebsiteDataStore.default().httpCookieStore.delete(cookie) {}
            }
        }
        for cookie in HTTPCookieStorage.shared.cookies ?? []
            where cookie.domain.contains("chatgpt.com") || cookie.domain.contains("openai.com") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    // MARK: - Cookie Sync
    // WKWebView and URLSession use separate cookie jars.
    // Bridge WKWebView → HTTPCookieStorage.shared before any URLSession call.

    private func syncWebKitCookies() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                for cookie in cookies where
                    cookie.domain.contains("chatgpt.com") || cookie.domain.contains("openai.com") {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Token Refresh

    @discardableResult
    private func refreshAccessToken() async throws -> String {
        guard KeychainStore.load(forKey: "sessionToken") != nil else {
            isAuthenticated = false
            throw NetworkError.notAuthenticated
        }

        await syncWebKitCookies()

        var req = URLRequest(url: sessionEndpoint)
        req.setValue("https://chatgpt.com", forHTTPHeaderField: "Referer")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.info("[Auth] /api/auth/session → HTTP \(statusCode)")
            guard statusCode == 200, !data.isEmpty else {
                isAuthenticated = false
                KeychainStore.delete(forKey: "sessionToken")
                throw NetworkError.refreshFailed
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let session = try decoder.decode(SessionResponse.self, from: data)
            cachedAccessToken = session.accessToken
            tokenExpiresAt = parseExpiry(from: session.expires) ?? Date.now.addingTimeInterval(86400)
            isAuthenticated = true
            logger.info("[Auth] access token cached, expires: \(self.tokenExpiresAt?.description ?? "nil")")
            return session.accessToken
        } catch let e as NetworkError {
            logger.info("[Auth] NetworkError in refresh: \(e.localizedDescription)")
            if e.isAuthError {
                isAuthenticated = false
                KeychainStore.delete(forKey: "sessionToken")
            }
            throw e
        } catch let urlError as URLError {
            if urlError.code == .cancelled {
                // The surrounding Task was cancelled — propagate as CancellationError
                // so the caller silently ignores it instead of showing a network banner.
                logger.info("[Auth] URLError cancelled — task was cancelled, ignoring")
                throw CancellationError()
            }
            // Network-level failure — the token is likely still valid, just unreachable.
            // Don't clear auth state so the next refresh attempt can succeed.
            logger.info("[Auth] URLError in refresh: \(urlError.localizedDescription)")
            throw NetworkError.networkUnavailable
        } catch {
            // Decode or other unexpected error — session is probably invalid.
            logger.info("[Auth] unexpected error in refresh: \(error)")
            isAuthenticated = false
            KeychainStore.delete(forKey: "sessionToken")
            throw NetworkError.refreshFailed
        }
    }

    private func parseExpiry(from string: String?) -> Date? {
        guard let string else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: string) ?? {
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            return f2.date(from: string)
        }()
    }

    // MARK: - Keychain bootstrap

    private func loadSessionFromKeychain() {
        guard KeychainStore.load(forKey: "sessionToken") != nil else { return }
        isAuthenticated = true
    }
}

// MARK: - Login Window Controller

@MainActor
final class LoginWindowController: NSObject {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var cookieObserver: CookieObserver?
    private let onComplete: (Result<String, Error>) -> Void
    private let targetURL: URL
    private var hasCompleted = false
    private let logger = Logger(subsystem: "ai.quota", category: "codex-login")

    init(baseURL: URL, onComplete: @escaping (Result<String, Error>) -> Void) {
        self.targetURL = baseURL
        self.onComplete = onComplete
    }

    func show() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        // Check for existing session cookie — if found, complete immediately
        // without showing any window. Use Task {@MainActor} for proper isolation.
        config.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }

            if let sessionCookie = cookies.first(where: {
                $0.name == "__Secure-next-auth.session-token" && $0.domain.contains("chatgpt.com")
            }) {
                // Sync all cookies to URLSession before completing
                for cookie in cookies where
                    cookie.domain.contains("chatgpt.com") || cookie.domain.contains("openai.com") {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                let value = sessionCookie.value
                Task { @MainActor [weak self] in
                    self?.complete(with: .success(value))
                }
                return
            }

            // Not logged in — show the browser window
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.showWindow(config: config)
            }
        }
    }

    private func showWindow(config: WKWebViewConfiguration) {
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 520, height: 680), configuration: config)
        webView.navigationDelegate = self  // didFinish fires after every page load
        self.webView = webView

        // CookieObserver fires when cookies *change* — catches fresh logins
        let observer = CookieObserver { [weak self] sessionToken in
            Task { @MainActor [weak self] in
                self?.complete(with: .success(sessionToken))
            }
        }
        config.websiteDataStore.httpCookieStore.add(observer)
        self.cookieObserver = observer

        let win = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Sign in to ChatGPT"
        win.contentView = webView
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        self.window = win

        webView.load(URLRequest(url: targetURL))
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func complete(with result: Result<String, Error>) {
        guard !hasCompleted else { return }
        hasCompleted = true
        window?.close()
        window = nil
        webView = nil
        cookieObserver = nil
        onComplete(result)
    }
}

// MARK: - WKNavigationDelegate

@MainActor
extension LoginWindowController: WKNavigationDelegate {
    /// Called after every page load.
    /// Strategy:
    ///   1. If on /api/auth/session → read JWT from page body via JS; sync cookies; complete.
    ///   2. Otherwise check for __Secure-next-auth.session-token cookie.
    ///   3. If logged-in page but no session cookie → navigate to /api/auth/session.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let currentURL = webView.url else { return }
        logger.info("[Auth] didFinish: \(currentURL.path)")

        // ── Case 1: We're on /api/auth/session — read the JWT from the page body ──
        if currentURL.host?.contains("chatgpt.com") == true,
           currentURL.path == "/api/auth/session" {
            webView.evaluateJavaScript("document.body.innerText") { [weak self] result, _ in
                guard let self, !self.hasCompleted else { return }
                guard let text = result as? String, let data = text.data(using: .utf8) else {
                    self.logger.info("[Auth] /api/auth/session body unreadable — not logged in")
                    return
                }

                struct SessionBody: Decodable { let accessToken: String? }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase

                guard let body = try? decoder.decode(SessionBody.self, from: data),
                      body.accessToken != nil else {
                    self.logger.info("[Auth] no accessToken in /api/auth/session — redirecting to login page")
                    guard !self.hasCompleted else { return }
                    let loginURL = URL(string: "https://chatgpt.com/auth/login")!
                    webView.load(URLRequest(url: loginURL))
                    return
                }

                // Sync all chatgpt.com / openai.com cookies to URLSession before completing
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self, !self.hasCompleted else { return }
                    for cookie in cookies where
                        cookie.domain.contains("chatgpt.com") || cookie.domain.contains("openai.com") {
                        HTTPCookieStorage.shared.setCookie(cookie)
                    }
                    self.logger.info("[Auth] synced \(cookies.count) cookies → completing")
                    // Pass a sentinel — AuthManager.refreshAccessToken() will re-call
                    // /api/auth/session via URLSession using the now-synced cookies.
                    Task { @MainActor [weak self] in
                        self?.complete(with: .success("session-via-cookies"))
                    }
                }
            }
            return
        }

        // ── Case 2: Any other page — check for the classic session-token cookie ──
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            if let sessionCookie = cookies.first(where: {
                $0.name == "__Secure-next-auth.session-token" && $0.domain.contains("chatgpt.com")
            }) {
                self.logger.info("[Auth] found session-token cookie ✓")
                for cookie in cookies where
                    cookie.domain.contains("chatgpt.com") || cookie.domain.contains("openai.com") {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                let value = sessionCookie.value
                Task { @MainActor [weak self] in
                    self?.complete(with: .success(value))
                }
            } else if currentURL.host?.contains("chatgpt.com") == true,
                      !currentURL.path.hasPrefix("/auth/"),
                      !currentURL.path.hasPrefix("/login") {
                // Appears logged in (not on an auth page) but session token missing —
                // navigate directly to /api/auth/session to read the JWT.
                self.logger.info("[Auth] appears logged in but no session cookie — navigating to /api/auth/session")
                let sessionURL = URL(string: "https://chatgpt.com/api/auth/session")!
                Task { @MainActor [weak self] in
                    guard let self, !self.hasCompleted else { return }
                    webView.load(URLRequest(url: sessionURL))
                }
            } else {
                self.logger.info("[Auth] waiting for user to log in on \(currentURL.path)")
            }
        }
    }
}

@MainActor
extension LoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard !hasCompleted else { return }
        complete(with: .failure(NetworkError.notAuthenticated))
    }
}

// MARK: - Cookie Observer

private final class CookieObserver: NSObject, WKHTTPCookieStoreObserver, @unchecked Sendable {
    private let onSessionToken: @Sendable (String) -> Void
    private var hasFound = false

    init(onSessionToken: @Sendable @escaping (String) -> Void) {
        self.onSessionToken = onSessionToken
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard !hasFound else { return }
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self, !self.hasFound else { return }
            if let sessionCookie = cookies.first(where: {
                $0.name == "__Secure-next-auth.session-token" && $0.domain.contains("chatgpt.com")
            }) {
                self.hasFound = true
                for cookie in cookies where
                    cookie.domain.contains("chatgpt.com") || cookie.domain.contains("openai.com") {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                let value = sessionCookie.value
                self.onSessionToken(value)
            }
        }
    }
}
