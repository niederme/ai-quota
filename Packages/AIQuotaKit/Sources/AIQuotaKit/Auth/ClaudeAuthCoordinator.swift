import Foundation
import WebKit
import AppKit
import os

// MARK: - Probe types

public enum ClaudeProbeResult: Sendable {
    case found(orgId: String, cookies: [HTTPCookie])
    case notFound
}

// MARK: - Request context

/// Value type the coordinator produces for authenticated requests.
public struct ClaudeRequestContext: Sendable {
    public let orgId: String
}

// MARK: - ClaudeAuthCoordinator

/// Owns all Claude auth state and WebKit I/O.
/// WebKit is only read inside transitions; results are recorded here.
/// All other code receives state via stateStream or requestContext().
public actor ClaudeAuthCoordinator {

    // MARK: Persistence keys

    private static let signedOutKey    = "claude.signedOutByUser"
    private static let freshInstallKey = "app.installedAt.v2"  // shared with CodexAuthCoordinator

    // MARK: State

    public private(set) var state: AuthState = .unknown
    private var continuations: [UUID: AsyncStream<AuthState>.Continuation] = [:]

    // MARK: Auth context (captured during transitions)

    private var capturedOrgId: String?
    private var capturedCookies: [HTTPCookie] = []
    private var cachedOAuthCredentials: ClaudeOAuthCredentials?

    // MARK: Logger

    private let logger = Logger(subsystem: "ai.quota", category: "claude-coord")

    // MARK: Probe injection

    /// Real probe reads WKWebsiteDataStore.default(). Tests inject a mock.
    public typealias SessionProbe = @Sendable () async -> ClaudeProbeResult
    public typealias OAuthCredentialsLoader = @Sendable (_ allowKeychain: Bool) throws -> ClaudeOAuthCredentials
    private let probe: SessionProbe
    private let oauthCredentialsLoader: OAuthCredentialsLoader

    public init(
        probe: SessionProbe? = nil,
        oauthCredentialsLoader: OAuthCredentialsLoader? = nil
    ) {
        self.probe = probe ?? ClaudeAuthCoordinator.wkProbe
        self.oauthCredentialsLoader = oauthCredentialsLoader ?? { allowKeychain in
            try ClaudeOAuthCredentialsStore.loadUsable(
                keychainReader: allowKeychain ? .claudeCodeInteractive : nil
            )
        }
    }

    // MARK: - State stream

    /// Emits the current state immediately on subscription, then subsequent transitions.
    public nonisolated var stateStream: AsyncStream<AuthState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(continuation: continuation, id: id) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id: id) }
            }
        }
    }

    private func register(continuation: AsyncStream<AuthState>.Continuation, id: UUID) {
        continuations[id] = continuation
        continuation.yield(state)
    }

    private func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func transition(to newState: AuthState) {
        state = newState
        logger.info("[ClaudeCoord] → \(String(describing: newState))")
        for c in continuations.values { c.yield(newState) }
    }

    // MARK: - Bootstrap

    /// Called once at process start. Safe to call multiple times; subsequent calls are no-ops.
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
        case .found(let orgId, let cookies):
            cachedOAuthCredentials = nil
            capturedOrgId = orgId
            capturedCookies = cookies
            injectCookies(cookies)
            persistSharedAuthContext()
            transition(to: .authenticated)
        case .notFound, .none:
            if restoreFromSharedAuthContext() {
                transition(to: .authenticated)
            } else if restoreFromOAuthCredentials(allowKeychain: false) {
                transition(to: .authenticated)
            } else {
                SharedAuthContextStore.clearClaude()
                transition(to: .unauthenticated)
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
        SharedDefaults.clearUsage()
        SharedDefaults.clearClaudeUsage()
        // Do not clear WebKit cookies here. A misclassified update/archive build
        // can otherwise destroy a valid Claude session before the probe can use it.
        UserDefaults.standard.set(true, forKey: sentinel)
    }

    // MARK: - signIn()

    /// Legal from: unauthenticated, signedOutByUser.
    /// Throws invalidTransition from all other states.
    public func signIn() async throws {
        switch state {
        case .unauthenticated, .signedOutByUser: break
        default: throw AuthCoordinatorError.invalidTransition(from: state)
        }

        transition(to: .signingIn)

        if restoreFromOAuthCredentials(allowKeychain: true) {
            UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
            transition(to: .authenticated)
            return
        }

        if case .found(let orgId, let cookies) = await withProbeTimeout(probe) {
            cachedOAuthCredentials = nil
            capturedOrgId = orgId
            capturedCookies = cookies
            injectCookies(cookies)
            persistSharedAuthContext()
            UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
            transition(to: .authenticated)
            return
        }

        do {
            let (orgId, cookies) = try await runLoginWindow()
            cachedOAuthCredentials = nil
            capturedOrgId = orgId
            capturedCookies = cookies
            injectCookies(cookies)
            persistSharedAuthContext()
            UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
            transition(to: .authenticated)
        } catch {
            SharedAuthContextStore.clearClaude()
            transition(to: .unauthenticated)
            throw error
        }
    }

    // MARK: - signOut()

    /// Legal from: authenticated (real transition).
    /// No-op from: unauthenticated, signedOutByUser.
    /// Throws invalidTransition from transient states.
    public func signOut() async throws {
        switch state {
        case .unauthenticated, .signedOutByUser:
            return  // explicit no-op
        case .authenticated:
            break
        default:
            throw AuthCoordinatorError.invalidTransition(from: state)
        }

        transition(to: .signingOut)
        UserDefaults.standard.set(true, forKey: Self.signedOutKey)
        clearAuthContext()
        await clearWKCookies()
        await verifyWKCookiesEmpty()
        transition(to: .signedOutByUser)
    }

    // MARK: - revalidateSessionAfterAuthFailure()

    /// Legal from: authenticated. Returns false from all other states (no transition).
    @discardableResult
    public func revalidateSessionAfterAuthFailure() async -> Bool {
        guard state == .authenticated else { return false }

        if restoreFromOAuthCredentials(allowKeychain: false) {
            return true
        }

        let result = await withProbeTimeout(probe)

        // Re-check: another transition (e.g. signOut) may have run while probe was in flight.
        guard state == .authenticated else { return false }

        switch result {
        case .found(let orgId, let cookies):
            cachedOAuthCredentials = nil
            capturedOrgId = orgId
            capturedCookies = cookies
            injectCookies(cookies)
            persistSharedAuthContext()
            return true
        case .notFound, .none:
            clearAuthContext()
            transition(to: .unauthenticated)
            return false
        }
    }

    // MARK: - reset()

    /// Legal from: authenticated, unauthenticated, signedOutByUser.
    /// If signingIn or signingOut is in progress, waits for it to settle first.
    public func reset() async {
        // Wait up to 30 seconds for any in-flight transient transition to settle.
        let deadline = Date.now.addingTimeInterval(30)
        while (state == .signingIn || state == .signingOut || state == .resetting),
              Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard state == .authenticated || state == .unauthenticated || state == .signedOutByUser else {
            logger.warning("[ClaudeCoord] reset: timed out waiting for in-flight transition to settle; forcing signedOutByUser")
            UserDefaults.standard.set(true, forKey: Self.signedOutKey)
            clearAuthContext()
            transition(to: .signedOutByUser)
            return
        }

        transition(to: .resetting)
        UserDefaults.standard.set(true, forKey: Self.signedOutKey)
        clearAuthContext()
        await clearWKCookies()
        let verified = await verifyWKCookiesEmpty()
        if !verified {
            logger.warning("[ClaudeCoord] reset: WebKit teardown could not be fully verified")
        }
        transition(to: .signedOutByUser)
    }

    // MARK: - requestContext()

    /// Called by ClaudeClient before each request.
    /// Ensures captured cookies are in HTTPCookieStorage and returns orgId.
    /// Throws notAuthenticated if the coordinator is not in authenticated state.
    public func requestContext() async throws -> ClaudeRequestContext {
        guard state == .authenticated, let orgId = capturedOrgId else {
            throw NetworkError.notAuthenticated
        }
        injectCookies(capturedCookies)
        return ClaudeRequestContext(orgId: orgId)
    }

    public func loadOAuthCredentials(allowKeychain: Bool) throws -> ClaudeOAuthCredentials {
        let fileError: Error?
        do {
            let credentials = try oauthCredentialsLoader(false)
            cachedOAuthCredentials = nil
            return credentials
        } catch {
            fileError = error
        }

        if let cachedOAuthCredentials,
           !cachedOAuthCredentials.isExpired,
           cachedOAuthCredentials.hasRequiredScope {
            return cachedOAuthCredentials
        }

        guard allowKeychain else {
            throw fileError ?? ClaudeOAuthCredentialsError.notFound
        }

        let credentials = try oauthCredentialsLoader(true)
        cachedOAuthCredentials = credentials
        return credentials
    }

    public func invalidateCachedOAuthCredentials() {
        cachedOAuthCredentials = nil
    }

    // MARK: - Private helpers

    private func clearAuthContext() {
        cachedOAuthCredentials = nil
        capturedOrgId = nil
        capturedCookies = []
        SharedAuthContextStore.clearClaude()
        for cookie in HTTPCookieStorage.shared.cookies ?? []
            where cookie.domain.contains("claude.ai") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private func persistSharedAuthContext() {
        guard let capturedOrgId else { return }
        SharedAuthContextStore.saveClaude(orgId: capturedOrgId, cookies: capturedCookies)
    }

    private func restoreFromSharedAuthContext() -> Bool {
        guard let context = SharedAuthContextStore.loadClaude() else { return false }
        cachedOAuthCredentials = nil
        capturedOrgId = context.orgId
        capturedCookies = context.httpCookies
        injectCookies(capturedCookies)
        return !context.orgId.isEmpty
    }

    private func restoreFromOAuthCredentials(allowKeychain: Bool) -> Bool {
        guard (try? loadOAuthCredentials(allowKeychain: allowKeychain)) != nil else {
            return false
        }
        capturedOrgId = nil
        capturedCookies = []
        SharedAuthContextStore.clearClaude()
        return true
    }

    private func injectCookies(_ cookies: [HTTPCookie]) {
        for cookie in cookies { HTTPCookieStorage.shared.setCookie(cookie) }
    }

    private func clearWKCookies() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    let claude = cookies.filter { $0.domain.contains("claude.ai") }
                    guard !claude.isEmpty else { cont.resume(); return }
                    let g = DispatchGroup()
                    for c in claude { g.enter(); WKWebsiteDataStore.default().httpCookieStore.delete(c) { g.leave() } }
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
                    let remaining = cookies.filter { $0.domain.contains("claude.ai") }
                    cont.resume(returning: remaining.isEmpty)
                }
            }
        }
    }

    /// Runs the probe with a 10-second timeout. Returns nil on timeout.
    ///
    /// Uses withCheckedContinuation + OSAllocatedUnfairLock rather than withTaskGroup so the
    /// timeout can win without waiting for the probe task to finish. withTaskGroup waits for
    /// ALL child tasks before returning — if the probe is stuck in a WKHTTPCookieStore
    /// getAllCookies callback that never fires (e.g. after the web content process crashes),
    /// the group hangs forever. The atomic guard here ensures the continuation is resumed
    /// exactly once regardless of which side wins.
    private func withProbeTimeout(_ probe: @escaping SessionProbe) async -> ClaudeProbeResult? {
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

    // MARK: - Login window

    private func runLoginWindow() async throws -> (orgId: String, cookies: [HTTPCookie]) {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let controller = CoordLoginWindowController { result in
                    continuation.resume(with: result)
                }
                controller.show()
            }
        }
    }

    // MARK: - Default WKWebView probe

    private static var wkProbe: SessionProbe {
        {
            await withCheckedContinuation { (cont: CheckedContinuation<ClaudeProbeResult, Never>) in
                Task { @MainActor in
                    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                        let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
                        Task {
                            guard let orgId = await ClaudeAuthCoordinator.resolveOrgId(from: claudeCookies) else {
                                cont.resume(returning: .notFound)
                                return
                            }
                            cont.resume(returning: .found(orgId: orgId, cookies: claudeCookies))
                        }
                    }
                }
            }
        }
    }

    fileprivate static func resolveOrgId(from cookies: [HTTPCookie]) async -> String? {
        if let orgId = cookies.first(where: { $0.name == "lastActiveOrg" })?.value,
           !orgId.isEmpty {
            return orgId
        }
        guard let sessionKey = cookies.first(where: { $0.name == "sessionKey" })?.value,
              !sessionKey.isEmpty
        else { return nil }
        return await fetchOrgId(sessionKey: sessionKey)
    }

    private static func fetchOrgId(sessionKey: String) async -> String? {
        guard let url = URL(string: "https://claude.ai/api/organizations") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let organizations = try? JSONDecoder().decode([ClaudeWebOrganization].self, from: data)
            else { return nil }
            return organizations.first(where: { $0.hasChatCapability })?.uuid
                ?? organizations.first(where: { !$0.isAPIOnly })?.uuid
                ?? organizations.first?.uuid
        } catch {
            return nil
        }
    }
}

private struct ClaudeWebOrganization: Decodable {
    let uuid: String
    let capabilities: [String]?

    var normalizedCapabilities: Set<String> {
        Set((capabilities ?? []).map { $0.lowercased() })
    }

    var hasChatCapability: Bool {
        normalizedCapabilities.contains("chat")
    }

    var isAPIOnly: Bool {
        !normalizedCapabilities.isEmpty && normalizedCapabilities == ["api"]
    }
}

// MARK: - CoordLoginWindowController

/// Presents the WKWebView login window and resolves with the captured orgId and cookies,
/// or rejects if the user cancels. Internal to the coordinator.
@MainActor
private final class CoordLoginWindowController: NSObject {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var popupWindows: [NSWindow] = []
    private var cookieObserver: CoordCookieObserver?
    private var pollTimer: Timer?
    private var hasCompleted = false
    private var selfRetain: CoordLoginWindowController?  // keeps self alive until continuation resumes
    private let onComplete: (Result<(orgId: String, cookies: [HTTPCookie]), Error>) -> Void
    private let logger = Logger(subsystem: "ai.quota", category: "claude-login")

    init(onComplete: @escaping (Result<(orgId: String, cookies: [HTTPCookie]), Error>) -> Void) {
        self.onComplete = onComplete
    }

    func show() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 520, height: 680), configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView

        let observer = CoordCookieObserver { [weak self] orgId, cookies in
            Task { @MainActor [weak self] in self?.complete(orgId: orgId, cookies: cookies) }
        }
        config.websiteDataStore.httpCookieStore.add(observer)
        self.cookieObserver = observer

        let win = NSWindow(contentRect: .init(x: 0, y: 0, width: 520, height: 680),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Sign in to Claude"
        win.contentView = webView
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.delegate = self
        self.window = win

        selfRetain = self  // prevent deallocation until complete() or fail() resumes the continuation
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        // Window is revealed in didFinish once the login page has settled, hiding intermediate SPA states.
        win.alphaValue = 0
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollCookies() }
        }
    }

    private func stopPolling() { pollTimer?.invalidate(); pollTimer = nil }

    private func pollCookies() {
        guard !hasCompleted, let wv = webView else { stopPolling(); return }
        wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self, !self.hasCompleted else { return }
            let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
            Task { [weak self] in
                guard let orgId = await ClaudeAuthCoordinator.resolveOrgId(from: claudeCookies) else { return }
                await MainActor.run { [weak self] in
                    self?.complete(orgId: orgId, cookies: claudeCookies)
                }
            }
        }
    }

    private func complete(orgId: String, cookies: [HTTPCookie]) {
        guard !hasCompleted else { return }
        hasCompleted = true
        stopPolling()
        closePopupWindows()
        window?.close()
        window = nil; webView = nil; cookieObserver = nil
        let callback = onComplete
        selfRetain = nil  // allow deallocation after continuation resumes
        callback(.success((orgId: orgId, cookies: cookies)))
    }

    private func fail(with error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        stopPolling()
        closePopupWindows()
        window?.close()
        window = nil; webView = nil; cookieObserver = nil
        let callback = onComplete
        selfRetain = nil  // allow deallocation after continuation resumes
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
extension CoordLoginWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Reveal the window the first time the page finishes loading.
        if let win = window, win.alphaValue == 0 {
            win.makeKeyAndOrderFront(nil)
            win.alphaValue = 1
            NSApp.activate(ignoringOtherApps: true)
        }
        startPolling()
        tryAPIorgDetection(webView: webView)
    }

    private func tryAPIorgDetection(webView: WKWebView) {
        guard let url = webView.url,
              url.host?.contains("claude.ai") == true,
              !url.path.hasPrefix("/login"),
              !url.path.hasPrefix("/magic-link"),
              !url.path.hasPrefix("/auth"),
              !hasCompleted
        else { return }

        webView.callAsyncJavaScript("""
            const r = await fetch('/api/organizations', {credentials: 'include'});
            if (!r.ok) return null;
            const orgs = await r.json();
            if (!Array.isArray(orgs) || orgs.length === 0) return null;
            const org = orgs[0];
            return org.uuid || org.id || null;
        """, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self, !self.hasCompleted else { return }
            guard case .success(let value) = result,
                  let orgId = value as? String, !orgId.isEmpty
            else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
                Task { @MainActor [weak self] in
                    self?.complete(orgId: orgId, cookies: claudeCookies)
                }
            }
        }
    }
}

@MainActor
extension CoordLoginWindowController: WKUIDelegate {
    // claude.ai's "Continue with Google" runs its OAuth flow in a window.open()
    // popup (Google Identity Services, display=popup). Without hosting that
    // popup the flow dies silently and Anthropic shows a generic login error.
    // The popup shares the login webview's WKWebsiteDataStore, so the session
    // cookies it produces are visible to the existing cookie observer/polling.
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
extension CoordLoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Only the main login window cancels the flow; popup windows close
        // as part of the OAuth handshake and must not abort it.
        guard (notification.object as? NSWindow) === window else { return }
        guard !hasCompleted else { return }
        fail(with: NetworkError.notAuthenticated)
    }
}

// MARK: - CoordCookieObserver

private final class CoordCookieObserver: NSObject, WKHTTPCookieStoreObserver, @unchecked Sendable {
    private var hasFound = false
    private let onFound: @MainActor @Sendable (String, [HTTPCookie]) -> Void

    init(onFound: @MainActor @Sendable @escaping (String, [HTTPCookie]) -> Void) { self.onFound = onFound }

    func cookiesDidChange(in store: WKHTTPCookieStore) {
        store.getAllCookies { [weak self] cookies in
            Task { [weak self] in
                guard let self, !self.hasFound else { return }
                let claude = cookies.filter { $0.domain.contains("claude.ai") }
                guard let orgId = await ClaudeAuthCoordinator.resolveOrgId(from: claude) else { return }
                await MainActor.run {
                    guard !self.hasFound else { return }
                    self.hasFound = true
                    self.onFound(orgId, claude)
                }
            }
        }
    }
}
