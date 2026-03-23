import Foundation
import WebKit
import AppKit
import os

// MARK: - Probe types

public enum CodexProbeResult: Sendable {
    case found(sessionToken: String)
    case notFound
}

// MARK: - CodexAuthCoordinator

public actor CodexAuthCoordinator {

    private static let signedOutKey    = "codex.signedOutByUser"
    private static let freshInstallKey = "app.installedAt.v2"

    public private(set) var state: AuthState = .unknown
    private var continuations: [UUID: AsyncStream<AuthState>.Continuation] = [:]

    // JWT cache — owned entirely by the coordinator
    private var cachedAccessToken: String?
    private var tokenExpiresAt: Date?
    private let sessionEndpoint = URL(string: "https://chatgpt.com/api/auth/session")!

    private let logger = Logger(subsystem: "ai.quota", category: "codex-coord")

    public typealias SessionProbe = @Sendable () async -> CodexProbeResult
    private let probe: SessionProbe

    public init(probe: SessionProbe? = nil) {
        self.probe = probe ?? CodexAuthCoordinator.wkProbe
    }

    // MARK: - State stream

    public nonisolated var stateStream: AsyncStream<AuthState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(continuation: continuation, id: id) }
            continuation.onTermination = { _ in Task { await self.unregister(id: id) } }
        }
    }

    private func register(continuation: AsyncStream<AuthState>.Continuation, id: UUID) {
        continuations[id] = continuation
        continuation.yield(state)
    }

    private func unregister(id: UUID) { continuations.removeValue(forKey: id) }

    private func transition(to newState: AuthState) {
        state = newState
        logger.info("[CodexCoord] → \(String(describing: newState))")
        for c in continuations.values { c.yield(newState) }
    }

    // MARK: - Bootstrap

    public func bootstrap() async {
        guard state == .unknown else { return }

        await clearStateIfFreshInstall()

        if UserDefaults.standard.bool(forKey: Self.signedOutKey) {
            transition(to: .signedOutByUser)
            return
        }

        transition(to: .restoringSession)
        let result = await withProbeTimeout(probe)
        switch result {
        case .found(let token):
            KeychainStore.save(token, forKey: "sessionToken")
            if (try? await refreshAccessToken()) != nil {
                transition(to: .authenticated)
            } else {
                transition(to: .unauthenticated)
            }
        case .notFound, .none:
            transition(to: .unauthenticated)
        }
    }

    // MARK: - signIn()

    public func signIn() async throws {
        switch state {
        case .unauthenticated, .signedOutByUser: break
        default: throw AuthCoordinatorError.invalidTransition(from: state)
        }

        transition(to: .signingIn)

        do {
            let result = try await runLoginWindow()
            if !result.sessionToken.isEmpty {
                KeychainStore.save(result.sessionToken, forKey: "sessionToken")
            }
            // Cache the access token returned directly from the WKWebView — no extra URLSession call needed.
            cachedAccessToken = result.accessToken
            tokenExpiresAt = result.expiresAt ?? Date.now.addingTimeInterval(86400)
            UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
            transition(to: .authenticated)
        } catch {
            transition(to: .unauthenticated)
            throw error
        }
    }

    // MARK: - signOut()

    public func signOut() async throws {
        switch state {
        case .unauthenticated, .signedOutByUser:
            return
        case .authenticated:
            break
        default:
            throw AuthCoordinatorError.invalidTransition(from: state)
        }

        transition(to: .signingOut)
        UserDefaults.standard.set(true, forKey: Self.signedOutKey)
        clearTokenCache()
        KeychainStore.delete(forKey: "sessionToken")
        await clearWKCookies()
        clearURLSessionCookies()
        await verifyWKCookiesEmpty()
        transition(to: .signedOutByUser)
    }

    // MARK: - revalidateSessionAfterAuthFailure()

    @discardableResult
    public func revalidateSessionAfterAuthFailure() async -> Bool {
        guard state == .authenticated else { return false }

        let result = await withProbeTimeout(probe)

        // Re-check: another transition may have run while probe was in flight.
        guard state == .authenticated else { return false }

        switch result {
        case .found(let token):
            KeychainStore.save(token, forKey: "sessionToken")
            if (try? await refreshAccessToken()) != nil { return true }
            clearTokenCache()
            transition(to: .unauthenticated)
            return false
        case .notFound, .none:
            clearTokenCache()
            KeychainStore.delete(forKey: "sessionToken")
            transition(to: .unauthenticated)
            return false
        }
    }

    // MARK: - reset()

    public func reset() async {
        let deadline = Date.now.addingTimeInterval(30)
        while (state == .signingIn || state == .signingOut || state == .resetting),
              Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard state == .authenticated || state == .unauthenticated || state == .signedOutByUser else {
            logger.warning("[CodexCoord] reset: timed out waiting for in-flight transition to settle; forcing signedOutByUser")
            UserDefaults.standard.set(true, forKey: Self.signedOutKey)
            clearTokenCache()
            KeychainStore.delete(forKey: "sessionToken")
            transition(to: .signedOutByUser)
            return
        }

        transition(to: .resetting)
        UserDefaults.standard.set(true, forKey: Self.signedOutKey)
        clearTokenCache()
        KeychainStore.delete(forKey: "sessionToken")
        await clearWKCookies()
        clearURLSessionCookies()
        let verified = await verifyWKCookiesEmpty()
        if !verified { logger.warning("[CodexCoord] reset: WebKit teardown could not be fully verified") }
        transition(to: .signedOutByUser)
    }

    // MARK: - accessToken() (for OpenAIClient)

    public func accessToken() async throws -> String {
        guard state == .authenticated else { throw NetworkError.notAuthenticated }
        if let token = cachedAccessToken, let exp = tokenExpiresAt, exp.addingTimeInterval(-60) > .now {
            return token
        }
        return try await refreshAccessToken()
    }

    // MARK: - Private

    private func clearTokenCache() {
        cachedAccessToken = nil
        tokenExpiresAt = nil
    }

    private func clearURLSessionCookies() {
        for cookie in HTTPCookieStorage.shared.cookies ?? []
            where cookie.domain.contains("chatgpt.com") || cookie.domain.contains("openai.com") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private func clearWKCookies() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    let relevant = cookies.filter { $0.domain.contains("chatgpt.com") || $0.domain.contains("openai.com") }
                    guard !relevant.isEmpty else { cont.resume(); return }
                    let g = DispatchGroup()
                    for c in relevant { g.enter(); WKWebsiteDataStore.default().httpCookieStore.delete(c) { g.leave() } }
                    g.notify(queue: .main) { cont.resume() }
                }
            }
        }
    }

    @discardableResult
    private func verifyWKCookiesEmpty() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            Task { @MainActor in
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    let remaining = cookies.filter { $0.domain.contains("chatgpt.com") || $0.domain.contains("openai.com") }
                    cont.resume(returning: remaining.isEmpty)
                }
            }
        }
    }

    @discardableResult
    private func refreshAccessToken() async throws -> String {
        var req = URLRequest(url: sessionEndpoint)
        req.setValue("https://chatgpt.com", forHTTPHeaderField: "Referer")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
            throw NetworkError.refreshFailed
        }
        struct SessionResponse: Decodable { let accessToken: String; let expires: String? }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let session = try decoder.decode(SessionResponse.self, from: data)
        cachedAccessToken = session.accessToken
        tokenExpiresAt = parseExpiry(session.expires) ?? Date.now.addingTimeInterval(86400)
        return session.accessToken
    }

    private func parseExpiry(_ string: String?) -> Date? {
        guard let string else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: string)
    }

    private func withProbeTimeout(_ probe: @escaping SessionProbe) async -> CodexProbeResult? {
        await withCheckedContinuation { cont in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let probeTask = Task {
                let result = await probe()
                resumed.withLock { alreadyDone in
                    guard !alreadyDone else { return }
                    alreadyDone = true
                    cont.resume(returning: result)
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(10))
                resumed.withLock { alreadyDone in
                    guard !alreadyDone else { return }
                    alreadyDone = true
                    probeTask.cancel()
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func runLoginWindow() async throws -> CodexLoginResult {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let controller = CodexLoginWindowController { result in
                    continuation.resume(with: result)
                }
                controller.show()
            }
        }
    }

    private func clearStateIfFreshInstall() async {
        let sentinel = Self.freshInstallKey
        guard UserDefaults.standard.object(forKey: sentinel) == nil else { return }
        KeychainStore.delete(forKey: "sessionToken")
        SharedDefaults.clearUsage()
        SharedDefaults.clearClaudeUsage()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                let store = WKWebsiteDataStore.default()
                let types = WKWebsiteDataStore.allWebsiteDataTypes()
                store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
                    cont.resume()
                }
            }
        }
        UserDefaults.standard.set(true, forKey: sentinel)
    }

    private static var wkProbe: SessionProbe {
        {
            await withCheckedContinuation { cont in
                Task { @MainActor in
                    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                        guard let token = cookies.first(where: {
                            $0.name == "__Secure-next-auth.session-token" && $0.domain.contains("chatgpt.com")
                        }) else {
                            cont.resume(returning: .notFound)
                            return
                        }
                        for c in cookies where c.domain.contains("chatgpt.com") || c.domain.contains("openai.com") {
                            HTTPCookieStorage.shared.setCookie(c)
                        }
                        cont.resume(returning: .found(sessionToken: token.value))
                    }
                }
            }
        }
    }
}

// MARK: - CodexLoginResult

/// Returned by CodexLoginWindowController — carries both the session token (for Keychain)
/// and the access token JWT (for immediate caching, no extra URLSession round-trip needed).
struct CodexLoginResult {
    let sessionToken: String   // may be empty if the cookie wasn't found in WK store
    let accessToken: String    // JWT from /api/auth/session body
    let expiresAt: Date?
}

// MARK: - CodexLoginWindowController

/// Presents a WKWebView login window and resolves with a CodexLoginResult.
///
/// Auth detection strategy: on every chatgpt.com page load (via didFinish) and on every
/// cookie change (via CodexCookieObserver), we call callAsyncJavaScript to fetch
/// /api/auth/session from the page context. If the response contains an accessToken,
/// we complete immediately. No secondary navigation to the JSON endpoint is needed —
/// this avoids the "didFinish never fires for JSON endpoint" / "evaluateJavaScript hangs"
/// failure modes from the previous approach.
@MainActor
private final class CodexLoginWindowController: NSObject {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var cookieObserver: CodexCookieObserver?
    private var hasCompleted = false
    private var isFetchingSession = false
    private var selfRetain: CodexLoginWindowController?
    private let onComplete: (Result<CodexLoginResult, Error>) -> Void
    private let logger = Logger(subsystem: "ai.quota", category: "codex-login")

    init(onComplete: @escaping (Result<CodexLoginResult, Error>) -> Void) { self.onComplete = onComplete }

    func show() {
        selfRetain = self
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: .init(x: 0, y: 0, width: 520, height: 680), configuration: config)
        wv.navigationDelegate = self
        self.webView = wv

        let observer = CodexCookieObserver { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let wv = self.webView else { return }
                self.tryFetchSession(webView: wv)
            }
        }
        config.websiteDataStore.httpCookieStore.add(observer)
        self.cookieObserver = observer

        // Load chatgpt.com. didFinish will show the login window if needed,
        // or fetch the session silently if already logged in.
        wv.load(URLRequest(url: URL(string: "https://chatgpt.com")!))
    }

    /// Fetches /api/auth/session via JS fetch from the current page context.
    /// If the response contains an accessToken we complete; otherwise we just wait.
    private func tryFetchSession(webView: WKWebView) {
        guard !hasCompleted, !isFetchingSession else { return }
        guard webView.url?.host?.contains("chatgpt.com") == true else { return }
        isFetchingSession = true
        logger.info("[CodexLogin] tryFetchSession from \(webView.url?.path ?? "?")")

        webView.callAsyncJavaScript("""
            try {
                const r = await fetch('/api/auth/session', {
                    credentials: 'include',
                    headers: { 'Accept': 'application/json' }
                });
                if (!r.ok) return null;
                return await r.json();
            } catch(e) { return null; }
        """, arguments: [:], in: nil, in: .page) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, !self.hasCompleted else { return }
                self.isFetchingSession = false

                guard case .success(let value) = result,
                      let dict = value as? [String: Any],
                      let accessToken = dict["accessToken"] as? String,
                      !accessToken.isEmpty else {
                    self.logger.info("[CodexLogin] session fetch: no accessToken yet")
                    return
                }

                self.logger.info("[CodexLogin] session fetch succeeded — completing")
                let expiresAt = self.parseExpiry(dict["expires"] as? String)

                // Best-effort: sync WK cookies to shared URLSession storage.
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    for c in cookies where c.domain.contains("chatgpt.com") || c.domain.contains("openai.com") {
                        HTTPCookieStorage.shared.setCookie(c)
                    }
                }

                self.complete(CodexLoginResult(
                    sessionToken: "",   // wkProbe on next bootstrap will persist to Keychain
                    accessToken: accessToken,
                    expiresAt: expiresAt
                ))
            }
        }
    }

    private func showLoginWindow() {
        guard let webView, window == nil else { return }
        let win = NSWindow(contentRect: .init(x: 0, y: 0, width: 520, height: 680),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Sign in to ChatGPT"
        win.contentView = webView
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.delegate = self
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func complete(_ result: CodexLoginResult) {
        guard !hasCompleted else { return }
        hasCompleted = true
        window?.close()
        window = nil; webView = nil; cookieObserver = nil
        let callback = onComplete
        selfRetain = nil
        callback(.success(result))
    }

    private func fail(with error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        window?.close()
        window = nil; webView = nil; cookieObserver = nil
        let callback = onComplete
        selfRetain = nil
        callback(.failure(error))
    }

    private func parseExpiry(_ string: String?) -> Date? {
        guard let string else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: string)
    }
}

@MainActor
extension CodexLoginWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.host?.contains("chatgpt.com") == true else { return }
        logger.info("[CodexLogin] didFinish: \(url.path)")

        if url.path.hasPrefix("/auth/") || url.path == "/login" {
            // On a login/auth page — show the window so the user can sign in.
            showLoginWindow()
        } else {
            // On an authenticated chatgpt.com page — try to fetch the session.
            tryFetchSession(webView: webView)
        }
    }
}

@MainActor
extension CodexLoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard !hasCompleted else { return }
        fail(with: NetworkError.notAuthenticated)
    }
}

/// Fires when any cookie changes in the WK store, triggering a session fetch attempt.
private final class CodexCookieObserver: NSObject, WKHTTPCookieStoreObserver, @unchecked Sendable {
    private let onCookiesChanged: @MainActor @Sendable () -> Void
    init(onCookiesChanged: @MainActor @Sendable @escaping () -> Void) { self.onCookiesChanged = onCookiesChanged }

    func cookiesDidChange(in store: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in self?.onCookiesChanged() }
    }
}
