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

    private static let signedOutKey = "claude.signedOutByUser"

    // MARK: State

    public private(set) var state: AuthState = .unknown
    private var continuations: [UUID: AsyncStream<AuthState>.Continuation] = [:]

    // MARK: Auth context (captured during transitions)

    private var capturedOrgId: String?
    private var capturedCookies: [HTTPCookie] = []

    // MARK: Concurrency guards

    private var bootstrapTask: Task<Void, Never>?
    private var activeTransition: Task<Void, Never>?

    // MARK: Logger

    private let logger = Logger(subsystem: "ai.quota", category: "claude-coord")

    // MARK: Probe injection

    /// Real probe reads WKWebsiteDataStore.default(). Tests inject a mock.
    public typealias SessionProbe = @Sendable () async -> ClaudeProbeResult
    private let probe: SessionProbe

    public init(probe: SessionProbe? = nil) {
        self.probe = probe ?? ClaudeAuthCoordinator.wkProbe
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

        if UserDefaults.standard.bool(forKey: Self.signedOutKey) {
            transition(to: .signedOutByUser)
            return
        }

        transition(to: .restoringSession)
        let result = await withProbeTimeout(probe)
        switch result {
        case .found(let orgId, let cookies):
            capturedOrgId = orgId
            capturedCookies = cookies
            injectCookies(cookies)
            transition(to: .authenticated)
        case .notFound, .none:
            transition(to: .unauthenticated)
        }
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

        // Clear stale WKWebView cookies before the login window opens.
        await clearWKCookies()

        do {
            let (orgId, cookies) = try await runLoginWindow()
            capturedOrgId = orgId
            capturedCookies = cookies
            injectCookies(cookies)
            UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
            transition(to: .authenticated)
        } catch {
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

        let result = await withProbeTimeout(probe)
        switch result {
        case .found(let orgId, let cookies):
            capturedOrgId = orgId
            capturedCookies = cookies
            injectCookies(cookies)
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
        // Wait for any in-flight transient transition to settle.
        while state == .signingIn || state == .signingOut || state == .resetting {
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard state == .authenticated || state == .unauthenticated || state == .signedOutByUser else {
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

    // MARK: - Private helpers

    private func clearAuthContext() {
        capturedOrgId = nil
        capturedCookies = []
        for cookie in HTTPCookieStorage.shared.cookies ?? []
            where cookie.domain.contains("claude.ai") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
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
    private func withProbeTimeout(_ probe: @escaping SessionProbe) async -> ClaudeProbeResult? {
        await withTaskGroup(of: ClaudeProbeResult?.self) { group in
            group.addTask { await probe() }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
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
                        let loginCookies = ["lastActiveOrg", "sessionKey", "routingHint"]
                        guard claudeCookies.contains(where: { loginCookies.contains($0.name) }),
                              let orgId = claudeCookies.first(where: { $0.name == "lastActiveOrg" })?.value
                        else {
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

// MARK: - CoordLoginWindowController

/// Presents the WKWebView login window and resolves with the captured orgId and cookies,
/// or rejects if the user cancels. Internal to the coordinator.
@MainActor
private final class CoordLoginWindowController: NSObject {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var cookieObserver: CoordCookieObserver?
    private var pollTimer: Timer?
    private var hasCompleted = false
    private let onComplete: (Result<(orgId: String, cookies: [HTTPCookie]), Error>) -> Void
    private static let loginCookies = ["lastActiveOrg", "sessionKey", "routingHint"]
    private let logger = Logger(subsystem: "ai.quota", category: "claude-login")

    init(onComplete: @escaping (Result<(orgId: String, cookies: [HTTPCookie]), Error>) -> Void) {
        self.onComplete = onComplete
    }

    func show() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 520, height: 680), configuration: config)
        webView.navigationDelegate = self
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

        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
            guard claudeCookies.contains(where: { Self.loginCookies.contains($0.name) }),
                  let orgId = claudeCookies.first(where: { $0.name == "lastActiveOrg" })?.value
            else { return }
            Task { @MainActor [weak self] in self?.complete(orgId: orgId, cookies: claudeCookies) }
        }
    }

    private func complete(orgId: String, cookies: [HTTPCookie]) {
        guard !hasCompleted else { return }
        hasCompleted = true
        stopPolling()
        window?.close()
        window = nil; webView = nil; cookieObserver = nil
        onComplete(.success((orgId: orgId, cookies: cookies)))
    }

    private func fail(with error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        stopPolling()
        window?.close()
        window = nil; webView = nil; cookieObserver = nil
        onComplete(.failure(error))
    }
}

@MainActor
extension CoordLoginWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { startPolling() }
}

@MainActor
extension CoordLoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard !hasCompleted else { return }
        fail(with: NetworkError.notAuthenticated)
    }
}

// MARK: - CoordCookieObserver

private final class CoordCookieObserver: NSObject, WKHTTPCookieStoreObserver, @unchecked Sendable {
    private let onFound: @Sendable (String, [HTTPCookie]) -> Void
    private var hasFound = false
    private static let loginCookies = ["lastActiveOrg", "sessionKey", "routingHint"]

    init(onFound: @Sendable @escaping (String, [HTTPCookie]) -> Void) { self.onFound = onFound }

    func cookiesDidChange(in store: WKHTTPCookieStore) {
        guard !hasFound else { return }
        store.getAllCookies { [weak self] cookies in
            guard let self, !self.hasFound else { return }
            let claude = cookies.filter { $0.domain.contains("claude.ai") }
            guard claude.contains(where: { Self.loginCookies.contains($0.name) }),
                  let orgId = claude.first(where: { $0.name == "lastActiveOrg" })?.value
            else { return }
            self.hasFound = true
            self.onFound(orgId, claude)
        }
    }
}
