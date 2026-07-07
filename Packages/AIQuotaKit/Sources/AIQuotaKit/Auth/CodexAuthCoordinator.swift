import Foundation
import WebKit
import AppKit
import os

// MARK: - Probe types

public enum CodexProbeResult: Sendable {
    case found(sessionToken: String)
    case notFound
}

public enum CodexAuthSource: String, Codable, Sendable, Equatable {
    case codexOAuth
    case webSession
    case unknown
}

public struct CodexWebSessionResult: Sendable, Equatable {
    public let sessionToken: String
    public let accessToken: String
    public let expiresAt: Date?

    public init(sessionToken: String, accessToken: String, expiresAt: Date?) {
        self.sessionToken = sessionToken
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }
}

public struct CodexAccessContext: Sendable, Equatable {
    public let accessToken: String
    public let accountID: String?
    public let source: CodexAuthSource

    public init(accessToken: String, accountID: String?, source: CodexAuthSource) {
        self.accessToken = accessToken
        self.accountID = accountID
        self.source = source
    }
}

// MARK: - CodexAuthCoordinator

public actor CodexAuthCoordinator {

    private static let signedOutKey    = "codex.signedOutByUser"
    private static let freshInstallKey = "app.installedAt.v2"
    static let loginURL = URL(string: "https://chatgpt.com/auth/login")!

    public private(set) var state: AuthState = .unknown
    private var continuations: [UUID: AsyncStream<AuthState>.Continuation] = [:]

    // JWT cache — owned entirely by the coordinator
    private var cachedAccessToken: String?
    private var tokenExpiresAt: Date?
    private var accountID: String?
    private var authSource: CodexAuthSource?
    private var oauthDisabledForSession = false
    private let sessionEndpoint = URL(string: "https://chatgpt.com/api/auth/session")!

    private let logger = Logger(subsystem: "ai.quota", category: "codex-coord")

    public typealias SessionProbe = @Sendable () async -> CodexProbeResult
    public typealias HeadlessSessionReviver = @Sendable () async -> CodexWebSessionResult?
    public typealias AccessTokenRefresher = @Sendable (_ sessionToken: String) async throws -> (token: String, expiresAt: Date?)
    public typealias OAuthCredentialsLoader = @Sendable () throws -> CodexOAuthCredentials
    private let probe: SessionProbe
    private let headlessSessionReviver: HeadlessSessionReviver
    private let tokenRefresher: AccessTokenRefresher
    private let oauthCredentialsLoader: OAuthCredentialsLoader

    public init(
        probe: SessionProbe? = nil,
        headlessSessionReviver: HeadlessSessionReviver? = nil,
        tokenRefresher: AccessTokenRefresher? = nil,
        oauthCredentialsLoader: OAuthCredentialsLoader? = nil
    ) {
        self.probe = probe ?? CodexAuthCoordinator.wkProbe
        self.headlessSessionReviver = headlessSessionReviver ?? CodexAuthCoordinator.headlessWebSessionReviver
        self.tokenRefresher = tokenRefresher ?? CodexAuthCoordinator.defaultTokenRefresher
        self.oauthCredentialsLoader = oauthCredentialsLoader ?? {
            try CodexOAuthCredentialsStore.loadUsable()
        }
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
        logger.info("[CodexCoord] → \(String(describing: newState), privacy: .public)")
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
        if restoreFromOAuthCredentials() {
            transition(to: .authenticated)
            return
        }

        let result = await withProbeTimeout(probe)
        switch result {
        case .found(let token):
            if await restoreFromSessionToken(token) {
                transition(to: .authenticated)
            } else {
                clearPersistedSharedAuthContext()
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

        if restoreFromOAuthCredentials() {
            UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
            transition(to: .authenticated)
            return
        }

        do {
            let result = try await runLoginWindow()
            if !result.sessionToken.isEmpty {
                KeychainStore.save(result.sessionToken, forKey: "sessionToken")
            }
            // Cache the access token returned directly from the WKWebView — no extra URLSession call needed.
            cachedAccessToken = result.accessToken
            tokenExpiresAt = result.expiresAt ?? Date.now.addingTimeInterval(86400)
            accountID = CodexOAuthCredentialsStore.jwtAccountID(result.accessToken)
            authSource = .webSession
            persistSharedAuthContext(sessionToken: result.sessionToken)
            UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
            transition(to: .authenticated)
        } catch {
            clearPersistedSharedAuthContext()
            transition(to: .unauthenticated)
            throw error
        }
    }

    /// Best-effort recovery for already-enrolled installs that lose app-side
    /// Codex state after an app replacement. This mirrors the non-UI sign-in
    /// sources, including a headless WebKit page-context session fetch.
    @discardableResult
    public func restoreWithoutPromptIfPossible(allowSignedOutByUser: Bool = false) async -> Bool {
        logger.notice("[CodexRecovery] requested state=\(String(describing: self.state), privacy: .public) allowSignedOutByUser=\(allowSignedOutByUser)")
        switch state {
        case .unauthenticated:
            break
        case .signedOutByUser where allowSignedOutByUser:
            break
        default:
            logger.notice("[CodexRecovery] skipped unsupported state=\(String(describing: self.state), privacy: .public)")
            return false
        }

        logger.notice("[CodexRecovery] trying Codex OAuth file")
        if restoreFromOAuthCredentialsForRecovery() {
            UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
            transition(to: .authenticated)
            return true
        }

        logger.notice("[CodexRecovery] trying WebKit session probe")
        let probeResult = await withProbeTimeout(probe)
        if case .found(let token) = probeResult {
            if await restoreFromSessionToken(token) {
                logger.notice("[CodexRecovery] WebKit probe restored session")
                UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
                transition(to: .authenticated)
                return true
            }
            logger.notice("[CodexRecovery] WebKit probe token refresh failed")
        }

        switch probeResult {
        case .notFound:
            logger.notice("[CodexRecovery] WebKit probe did not find a Codex session")
        case .none:
            logger.notice("[CodexRecovery] WebKit probe timed out")
        case .found:
            break
        }

        logger.notice("[CodexRecovery] trying headless WebKit session revival")
        if let headlessResult = await headlessSessionReviver() {
            logger.notice("[CodexRecovery] headless WebKit revival found sessionToken=\(!headlessResult.sessionToken.isEmpty, privacy: .public)")
            restoreFromWebSession(headlessResult)
            UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
            transition(to: .authenticated)
            return true
        }

        logger.notice("[CodexRecovery] headless WebKit revival did not find a Codex session")
        return false
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
        clearPersistedSharedAuthContext()
        await clearWKCookies()
        clearURLSessionCookies()
        await verifyWKCookiesEmpty()
        transition(to: .signedOutByUser)
    }

    // MARK: - revalidateSessionAfterAuthFailure()

    @discardableResult
    public func revalidateSessionAfterAuthFailure() async -> Bool {
        guard state == .authenticated else { return false }

        if restoreFromOAuthCredentials() {
            return true
        }

        let result = await withProbeTimeout(probe)

        // Re-check: another transition may have run while probe was in flight.
        guard state == .authenticated else { return false }

        switch result {
        case .found(let token):
            KeychainStore.save(token, forKey: "sessionToken")
            persistSharedAuthContext(sessionToken: token)
            if (try? await refreshAccessToken()) != nil { return true }
            clearTokenCache()
            clearPersistedSharedAuthContext()
            transition(to: .unauthenticated)
            return false
        case .notFound, .none:
            clearTokenCache()
            KeychainStore.delete(forKey: "sessionToken")
            clearPersistedSharedAuthContext()
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
            clearPersistedSharedAuthContext()
            transition(to: .signedOutByUser)
            return
        }

        transition(to: .resetting)
        UserDefaults.standard.set(true, forKey: Self.signedOutKey)
        clearTokenCache()
        KeychainStore.delete(forKey: "sessionToken")
        clearPersistedSharedAuthContext()
        await clearWKCookies()
        clearURLSessionCookies()
        let verified = await verifyWKCookiesEmpty()
        if !verified { logger.warning("[CodexCoord] reset: WebKit teardown could not be fully verified") }
        transition(to: .signedOutByUser)
    }

    // MARK: - accessToken() (for OpenAIClient)

    public func accessToken() async throws -> String {
        let context = try await accessContext()
        return context.accessToken
    }

    public func accessContext() async throws -> CodexAccessContext {
        guard state == .authenticated else { throw NetworkError.notAuthenticated }

        if restoreFromOAuthCredentials() {
            guard let token = cachedAccessToken else { throw NetworkError.notAuthenticated }
            return CodexAccessContext(accessToken: token, accountID: accountID, source: .codexOAuth)
        }

        if let token = cachedAccessToken, let exp = tokenExpiresAt, exp.addingTimeInterval(-60) > .now {
            return CodexAccessContext(accessToken: token, accountID: accountID, source: authSource ?? .webSession)
        }
        let token = try await refreshAccessToken()
        return CodexAccessContext(accessToken: token, accountID: accountID, source: .webSession)
    }

    public func disableOAuthForSession() {
        oauthDisabledForSession = true
        if authSource == .codexOAuth {
            clearTokenCache()
        }
    }

    // MARK: - Private

    private func clearTokenCache() {
        cachedAccessToken = nil
        tokenExpiresAt = nil
        accountID = nil
        authSource = nil
    }

    private func restoreFromOAuthCredentials() -> Bool {
        guard !oauthDisabledForSession else { return false }
        guard let credentials = try? oauthCredentialsLoader() else { return false }
        cachedAccessToken = credentials.accessToken
        tokenExpiresAt = credentials.expiresAt ?? Date.now.addingTimeInterval(3600)
        accountID = credentials.accountID
        authSource = .codexOAuth
        persistSharedAuthContext(sessionToken: "")
        return true
    }

    private func restoreFromOAuthCredentialsForRecovery() -> Bool {
        guard !oauthDisabledForSession else {
            logger.notice("[CodexRecovery] Codex OAuth file failed reason=disabledForSession")
            return false
        }
        do {
            let credentials = try oauthCredentialsLoader()
            cachedAccessToken = credentials.accessToken
            tokenExpiresAt = credentials.expiresAt ?? Date.now.addingTimeInterval(3600)
            accountID = credentials.accountID
            authSource = .codexOAuth
            persistSharedAuthContext(sessionToken: "")
            logger.notice("[CodexRecovery] Codex OAuth file usable")
            return true
        } catch {
            logger.notice("[CodexRecovery] Codex OAuth file failed reason=\(Self.recoveryErrorDescription(error), privacy: .public)")
            return false
        }
    }

    private static func recoveryErrorDescription(_ error: Error) -> String {
        switch error {
        case CodexOAuthCredentialsError.notFound:
            return "notFound"
        case CodexOAuthCredentialsError.decodeFailed:
            return "decodeFailed"
        case CodexOAuthCredentialsError.missingTokens:
            return "missingTokens"
        case CodexOAuthCredentialsError.missingAccessToken:
            return "missingAccessToken"
        case CodexOAuthCredentialsError.expired:
            return "expired"
        default:
            return String(describing: error)
        }
    }

    private func restoreFromSessionToken(_ sessionToken: String) async -> Bool {
        guard !sessionToken.isEmpty else { return false }

        do {
            let refreshed = try await tokenRefresher(sessionToken)
            KeychainStore.save(sessionToken, forKey: "sessionToken")
            cachedAccessToken = refreshed.token
            tokenExpiresAt = refreshed.expiresAt ?? Date.now.addingTimeInterval(86400)
            accountID = CodexOAuthCredentialsStore.jwtAccountID(refreshed.token)
            authSource = .webSession
            persistSharedAuthContext(sessionToken: sessionToken)
            return true
        } catch {
            clearTokenCache()
            return false
        }
    }

    private func restoreFromWebSession(_ result: CodexWebSessionResult) {
        if !result.sessionToken.isEmpty {
            KeychainStore.save(result.sessionToken, forKey: "sessionToken")
        }
        cachedAccessToken = result.accessToken
        tokenExpiresAt = result.expiresAt ?? Date.now.addingTimeInterval(86400)
        accountID = CodexOAuthCredentialsStore.jwtAccountID(result.accessToken)
        authSource = .webSession
        persistSharedAuthContext(sessionToken: result.sessionToken)
    }

    private func persistSharedAuthContext(sessionToken: String? = nil) {
        let effectiveSessionToken = sessionToken ?? KeychainStore.load(forKey: "sessionToken") ?? ""
        SharedAuthContextStore.saveCodex(
            SharedCodexAuthContext(
                sessionToken: effectiveSessionToken,
                accessToken: cachedAccessToken,
                accessTokenExpiresAt: tokenExpiresAt,
                accountID: accountID
            )
        )
    }

    private func clearPersistedSharedAuthContext() {
        SharedAuthContextStore.clearCodex()
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
        accountID = CodexOAuthCredentialsStore.jwtAccountID(session.accessToken)
        authSource = .webSession
        persistSharedAuthContext()
        return session.accessToken
    }

    private static func defaultTokenRefresher(_ sessionToken: String) async throws -> (token: String, expiresAt: Date?) {
        guard !sessionToken.isEmpty else { throw NetworkError.notAuthenticated }

        var req = URLRequest(url: URL(string: "https://chatgpt.com/api/auth/session")!)
        req.setValue("https://chatgpt.com", forHTTPHeaderField: "Referer")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        req.setValue("__Secure-next-auth.session-token=\(sessionToken)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
            throw NetworkError.refreshFailed
        }

        struct SessionResponse: Decodable { let accessToken: String; let expires: String? }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let session = try decoder.decode(SessionResponse.self, from: data)
        return (
            token: session.accessToken,
            expiresAt: Self.parseExpiryValue(session.expires)
        )
    }

    private func parseExpiry(_ string: String?) -> Date? {
        Self.parseExpiryValue(string)
    }

    private static func parseExpiryValue(_ string: String?) -> Date? {
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
        guard !(await AuthInstallState.isExistingInstall()) else {
            UserDefaults.standard.set(true, forKey: sentinel)
            return
        }
        KeychainStore.delete(forKey: "sessionToken")
        SharedDefaults.clearUsage()
        SharedDefaults.clearClaudeUsage()
        // Do not clear WebKit cookies here. A misclassified update/archive build
        // can otherwise destroy valid provider sessions before probes can use them.
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

    private static var headlessWebSessionReviver: HeadlessSessionReviver {
        {
            await withCheckedContinuation { continuation in
                Task { @MainActor in
                    let reviver = CodexHeadlessSessionReviver { result in
                        continuation.resume(returning: result)
                    }
                    reviver.start()
                }
            }
        }
    }

    @MainActor
    fileprivate static func fetchSessionInPage(
        webView: WKWebView,
        completion: @escaping @MainActor (CodexWebSessionResult?) -> Void
    ) {
        webView.callAsyncJavaScript("""
            try {
                const r = await fetch('/api/auth/session', {
                    credentials: 'include',
                    headers: { 'Accept': 'application/json' }
                });
                if (!r.ok) return null;
                return await r.json();
            } catch(e) { return null; }
        """, arguments: [:], in: nil, in: .page) { result in
            Task { @MainActor in
                guard case .success(let value) = result,
                      let dict = value as? [String: Any],
                      let accessToken = dict["accessToken"] as? String,
                      !accessToken.isEmpty
                else {
                    completion(nil)
                    return
                }

                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                for cookie in cookies where cookie.domain.contains("chatgpt.com") || cookie.domain.contains("openai.com") {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                let sessionToken = cookies.first {
                    $0.name == "__Secure-next-auth.session-token" && $0.domain.contains("chatgpt.com")
                }?.value ?? ""

                completion(CodexWebSessionResult(
                    sessionToken: sessionToken,
                    accessToken: accessToken,
                    expiresAt: parseExpiryValue(dict["expires"] as? String)
                ))
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

    init(sessionToken: String, accessToken: String, expiresAt: Date?) {
        self.sessionToken = sessionToken
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    init(_ session: CodexWebSessionResult) {
        self.sessionToken = session.sessionToken
        self.accessToken = session.accessToken
        self.expiresAt = session.expiresAt
    }
}

// MARK: - CodexHeadlessSessionReviver

@MainActor
private final class CodexHeadlessSessionReviver: NSObject {
    private var webView: WKWebView?
    private var timeoutTask: Task<Void, Never>?
    private var detectionRetryTask: Task<Void, Never>?
    private var selfRetain: CodexHeadlessSessionReviver?
    private var hasCompleted = false
    private var isFetchingSession = false
    private let onComplete: (@MainActor (CodexWebSessionResult?) -> Void)
    private let logger = Logger(subsystem: "ai.quota", category: "codex-coord")

    init(onComplete: @escaping (@MainActor (CodexWebSessionResult?) -> Void)) {
        self.onComplete = onComplete
    }

    func start() {
        selfRetain = self
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            await MainActor.run { [weak self] in
                self?.complete(nil, reason: "timeout")
            }
        }
        webView.load(URLRequest(url: CodexAuthCoordinator.loginURL))
    }

    private func tryFetchSession() {
        guard !hasCompleted, !isFetchingSession, let webView else { return }
        guard let url = webView.url,
              url.host?.contains("chatgpt.com") == true
        else { return }
        if url.path.hasPrefix("/auth/") || url.path == "/login" {
            logger.notice("[CodexRecovery] headless WebKit landed on auth path=\(url.path, privacy: .public)")
        }
        isFetchingSession = true
        CodexAuthCoordinator.fetchSessionInPage(webView: webView) { [weak self] result in
            guard let self, !self.hasCompleted else { return }
            self.isFetchingSession = false
            if let result {
                self.complete(result, reason: "found")
            } else {
                self.scheduleDetectionRetry()
            }
        }
    }

    private func scheduleDetectionRetry() {
        guard detectionRetryTask == nil, !hasCompleted else { return }
        detectionRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run { [weak self] in
                guard let self, !self.hasCompleted else { return }
                self.detectionRetryTask = nil
                self.tryFetchSession()
            }
        }
    }

    private func complete(_ result: CodexWebSessionResult?, reason: String) {
        guard !hasCompleted else { return }
        hasCompleted = true
        logger.notice("[CodexRecovery] headless WebKit completed reason=\(reason, privacy: .public)")
        timeoutTask?.cancel()
        timeoutTask = nil
        detectionRetryTask?.cancel()
        detectionRetryTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        let callback = onComplete
        selfRetain = nil
        callback(result)
    }
}

@MainActor
extension CodexHeadlessSessionReviver: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tryFetchSession()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.notice("[CodexRecovery] headless WebKit navigation failed error=\(String(describing: error), privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logger.notice("[CodexRecovery] headless WebKit provisional navigation failed error=\(String(describing: error), privacy: .public)")
    }
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
    private var popupWindows: [NSWindow] = []
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
        wv.uiDelegate = self
        self.webView = wv

        let observer = CodexCookieObserver { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let wv = self.webView else { return }
                self.tryFetchSession(webView: wv)
            }
        }
        config.websiteDataStore.httpCookieStore.add(observer)
        self.cookieObserver = observer

        // Show the window immediately so the user gets visual feedback right away.
        // didFinish handles the two cases: login page (window already visible, user signs in)
        // or authenticated page (tryFetchSession completes and closes the window).
        showLoginWindow()
        wv.load(URLRequest(url: CodexAuthCoordinator.loginURL))
    }

    /// Fetches /api/auth/session via JS fetch from the current page context.
    /// If the response contains an accessToken we complete; otherwise we just wait.
    private func tryFetchSession(webView: WKWebView) {
        guard !hasCompleted, !isFetchingSession else { return }
        guard webView.url?.host?.contains("chatgpt.com") == true else { return }
        isFetchingSession = true
        logger.info("[CodexLogin] tryFetchSession from \(webView.url?.path ?? "?")")

        CodexAuthCoordinator.fetchSessionInPage(webView: webView) { [weak self] session in
            Task { @MainActor [weak self] in
                guard let self, !self.hasCompleted else { return }
                self.isFetchingSession = false

                guard let session else {
                    self.logger.info("[CodexLogin] session fetch: no accessToken yet")
                    return
                }

                self.logger.info("[CodexLogin] session fetch succeeded — completing")
                self.complete(CodexLoginResult(session))
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
        closePopupWindows()
        window?.close()
        window = nil; webView = nil; cookieObserver = nil
        let callback = onComplete
        selfRetain = nil
        callback(.success(result))
    }

    private func fail(with error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        closePopupWindows()
        window?.close()
        window = nil; webView = nil; cookieObserver = nil
        let callback = onComplete
        selfRetain = nil
        callback(.failure(error))
    }

    fileprivate func closePopupWindows() {
        for win in popupWindows { win.close() }
        popupWindows.removeAll()
    }

    fileprivate func hostPopup(_ popup: WKWebView, title: String) {
        let win = NSWindow(contentRect: popup.frame,
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = title
        win.contentView = popup
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.center()
        win.makeKeyAndOrderFront(nil)
        popupWindows.append(win)
    }

    fileprivate func closePopupWindow(hosting webView: WKWebView) {
        popupWindows.removeAll { win in
            guard win.contentView === webView else { return false }
            win.close()
            return true
        }
    }

}

@MainActor
extension CodexLoginWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.host?.contains("chatgpt.com") == true else { return }
        logger.info("[CodexLogin] didFinish: \(url.path)")

        if url.path.hasPrefix("/auth/") || url.path == "/login" {
            // Login page — window is already visible, nothing extra needed.
        } else {
            // Authenticated chatgpt.com page — try to fetch the session.
            tryFetchSession(webView: webView)
        }
    }
}

@MainActor
extension CodexLoginWindowController: WKUIDelegate {
    // Third-party sign-in providers (Google, Apple) run their OAuth flows in
    // window.open() popups. Without hosting the popup the flow dies silently.
    // The popup shares the login webview's WKWebsiteDataStore, so resulting
    // session cookies reach the existing cookie observer.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: .init(x: 0, y: 0, width: 480, height: 640), configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        hostPopup(popup, title: "Sign in")
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        closePopupWindow(hosting: webView)
    }
}

@MainActor
extension CodexLoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Only the main login window cancels the flow; popup windows close
        // as part of the OAuth handshake and must not abort it.
        guard (notification.object as? NSWindow) === window else { return }
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
