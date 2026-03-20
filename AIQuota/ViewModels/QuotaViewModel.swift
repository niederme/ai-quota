import Foundation
import Network
import os
import AIQuotaKit
import WidgetKit
import Combine

@MainActor
@Observable
final class QuotaViewModel {

    private let logger = Logger(subsystem: "ai.quota", category: "refresh")

    // MARK: - Codex (OpenAI)

    var codexUsage: CodexUsage?
    var isCodexLoading = false
    var codexError: NetworkError?
    private(set) var isCodexAuthenticated: Bool = false

    let codexAuthManager: AuthManager
    private let codexClient: OpenAIClient

    // MARK: - Claude

    var claudeUsage: ClaudeUsage?
    var isClaudeLoading = false
    var claudeError: NetworkError?
    private(set) var isClaudeAuthenticated: Bool = false

    let claudeAuthManager: ClaudeAuthManager
    private let claudeClient: ClaudeClient

    // MARK: - Shared state

    var settings: AppSettings = SharedDefaults.loadSettings()
    /// Which service's panel is visible in the popover.
    var activeService: ServiceType = .codex

    // MARK: - Backward-compatible aliases (used by MenuBarIconView / AIQuotaApp)

    var usage: CodexUsage? { codexUsage }
    var isLoading: Bool { isCodexLoading || isClaudeLoading }
    var error: NetworkError? {
        get { codexError }
        set { codexError = newValue }
    }
    var isAuthenticated: Bool { isCodexAuthenticated }
    var authManager: AuthManager { codexAuthManager }

    // MARK: - Last refreshed

    var lastRefreshedAt: Date?

    // MARK: - Private

    private var refreshTask: Task<Void, Never>?
    private var authCancellable: AnyCancellable?
    private var claudeAuthCancellable: AnyCancellable?

    /// Tracks whether the last known network path was unsatisfied so we can
    /// detect a transition back online and refresh immediately.
    private var wasOffline = false
    /// Set to true once NWPathMonitor fires its first update. Prevents false-positive
    /// "No network connection" banners at launch before the monitor has settled.
    private var pathMonitorReady = false
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "ai.quota.pathmonitor")

    // MARK: - Init

    init() {
        let codexAuth  = AuthManager()
        let claudeAuth = ClaudeAuthManager()

        self.codexAuthManager  = codexAuth
        self.claudeAuthManager = claudeAuth
        self.codexClient       = OpenAIClient(authManager: codexAuth)
        self.claudeClient      = ClaudeClient(authManager: claudeAuth)

        self.isCodexAuthenticated  = codexAuth.isAuthenticated
        self.isClaudeAuthenticated = claudeAuth.isAuthenticated

        // Load cached data immediately
        codexUsage  = SharedDefaults.loadCachedUsage()
        claudeUsage = SharedDefaults.loadCachedClaudeUsage()

        // Default active service to first authenticated one
        if !codexAuth.isAuthenticated && claudeAuth.isAuthenticated {
            activeService = .claude
        }

        // Bridge ObservableObject → @Observable
        authCancellable = codexAuth.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.isCodexAuthenticated = value }

        claudeAuthCancellable = claudeAuth.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.isClaudeAuthenticated = value }

        // Request notification permission on launch
        if settings.notificationsEnabled {
            Task { await NotificationManager.shared.requestPermission() }
        }

        // Start path monitor first so currentPath is valid before the first fetch
        startPathMonitor()

        // Kick off refresh immediately on launch so data is never stale
        if codexAuth.isAuthenticated || claudeAuth.isAuthenticated {
            startAutoRefresh()
        }
    }

    // MARK: - Network path monitor

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isNowSatisfied = path.status == .satisfied
            DispatchQueue.main.async {
                let isFirstFire = !self.pathMonitorReady
                self.pathMonitorReady = true
                if isFirstFire || !isNowSatisfied {
                    self.logger.info("[PathMonitor] status=\(isNowSatisfied ? "satisfied" : "unsatisfied") firstFire=\(isFirstFire)")
                }
                if isNowSatisfied {
                    // Always clear stale network-unavailable banners when path is
                    // satisfied — catches the launch-time false-positive where the
                    // first fetch fails before the monitor has run even once.
                    if case .networkUnavailable = self.codexError  { self.codexError  = nil }
                    if case .networkUnavailable = self.claudeError { self.claudeError = nil }
                    if self.wasOffline || isFirstFire {
                        // Came back online (or first monitor event) — fire an immediate
                        // refresh to recover from any startup errors that were suppressed.
                        self.wasOffline = false
                        guard self.isCodexAuthenticated || self.isClaudeAuthenticated else { return }
                        Task { await self.refresh() }
                    }
                } else {
                    self.wasOffline = true
                }
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    /// Returns true only for URLErrors that indicate genuine connectivity loss,
    /// as opposed to transient server/SSL/timeout errors that don't mean the
    /// device is actually offline.
    private func isConnectivityError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .dnsLookupFailed,
             .cannotFindHost,
             .cannotConnectToHost,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    // MARK: - Refresh

    func refresh() async {
        async let _ = refreshCodex()
        async let _ = refreshClaude()
        // Reload widgets once after both fetches complete so they always
        // get a consistent snapshot (not mid-refresh with one service stale).
        WidgetCenter.shared.reloadTimelines(ofKind: "AIQuotaWidget")
    }

    func refreshCodex() async {
        if !isCodexAuthenticated { await codexAuthManager.silentSignInIfPossible() }
        guard !isCodexLoading, isCodexAuthenticated else { return }
        isCodexLoading = true
        codexError = nil
        defer { isCodexLoading = false }

        do {
            let result = try await codexClient.fetchUsage()
            codexUsage = result
            lastRefreshedAt = .now
            SharedDefaults.saveUsage(result)
            if settings.notificationsEnabled {
                await NotificationManager.shared.evaluate(current: result)
            }
        } catch let e as NetworkError {
            if e.isAuthError {
                codexUsage = nil
                SharedDefaults.clearUsage()
                // Keychain said authenticated but session is invalid — try silent re-auth once.
                codexAuthManager.isAuthenticated = false
                if await codexAuthManager.silentSignInIfPossible() {
                    await refreshCodex()
                    return
                }
            } else if case .networkUnavailable = e, !pathMonitorReady {
                // Path monitor hasn't settled yet — suppress the banner to avoid
                // the false-positive "No network connection" flash at launch.
                logger.info("[CodexRefresh] suppressing networkUnavailable: pathMonitor not ready yet")
                return
            }
            codexError = e
        } catch is CancellationError {
            // Task was cancelled (e.g. a new refresh cycle started) — ignore silently
        } catch {
            // URLError.cancelled means the surrounding Task was cancelled — ignore silently
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            let pathStatus = pathMonitor.currentPath.status
            logger.warning("[CodexRefresh] unexpected error: \(error) | path: \(String(describing: pathStatus)) | urlErrCode: \(String(describing: (error as? URLError)?.code.rawValue))")
            // Only surface as network-unavailable if the error is truly connectivity-
            // related, or if NWPathMonitor independently confirms we're offline.
            // Require pathMonitorReady to avoid false-positives at launch before
            // the monitor has fired its first update.
            if isConnectivityError(error) || (pathMonitorReady && pathStatus != .satisfied) {
                codexError = .networkUnavailable
            }
        }
    }

    func refreshClaude() async {
        if !isClaudeAuthenticated { await claudeAuthManager.silentSignInIfPossible() }
        guard !isClaudeLoading, isClaudeAuthenticated else { return }
        isClaudeLoading = true
        claudeError = nil
        defer { isClaudeLoading = false }

        do {
            let result = try await claudeClient.fetchUsage()
            claudeUsage = result
            lastRefreshedAt = .now
            SharedDefaults.saveClaudeUsage(result)
            if settings.notificationsEnabled {
                await NotificationManager.shared.evaluate(claude: result)
            }
        } catch let e as NetworkError {
            if e.isAuthError {
                claudeUsage = nil
                SharedDefaults.clearClaudeUsage()
                // Keychain said authenticated but cookies are gone — try silent re-auth once.
                claudeAuthManager.isAuthenticated = false
                if await claudeAuthManager.silentSignInIfPossible() {
                    await refreshClaude()
                    return
                }
            } else if case .networkUnavailable = e, !pathMonitorReady {
                // Path monitor hasn't settled yet — suppress the banner to avoid
                // the false-positive "No network connection" flash at launch.
                logger.info("[ClaudeRefresh] suppressing networkUnavailable: pathMonitor not ready yet")
                return
            }
            claudeError = e
        } catch is CancellationError {
            // Task was cancelled (e.g. a new refresh cycle started) — ignore silently
        } catch {
            // URLError.cancelled means the surrounding Task was cancelled — ignore silently
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            let pathStatus = pathMonitor.currentPath.status
            logger.warning("[ClaudeRefresh] unexpected error: \(error) | path: \(String(describing: pathStatus)) | urlErrCode: \(String(describing: (error as? URLError)?.code.rawValue))")
            // Only surface as network-unavailable if the error is truly connectivity-
            // related, or if NWPathMonitor independently confirms we're offline.
            // Require pathMonitorReady to avoid false-positives at launch before
            // the monitor has fired its first update.
            if isConnectivityError(error) || (pathMonitorReady && pathStatus != .satisfied) {
                claudeError = .networkUnavailable
            }
        }
    }

    // MARK: - Auto-refresh

    func startAutoRefresh() {
        if settings.notificationsEnabled {
            Task { await NotificationManager.shared.requestPermission() }
        }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(settings.refreshInterval))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Sign In / Out

    func signIn() async {
        do {
            try await codexAuthManager.signIn()
            await refreshCodex()
            startAutoRefresh()
        } catch {
            codexError = .notAuthenticated
        }
    }

    func signInClaude() async {
        // Try silent re-auth first — if WKWebView session cookies are still
        // valid (e.g. after an app update) this avoids opening a login window.
        if await claudeAuthManager.silentSignInIfPossible() {
            logger.info("[SignIn] Claude silent re-auth succeeded, skipping login window")
            await refreshClaude()
            if !isCodexAuthenticated { startAutoRefresh() }
            return
        }
        do {
            try await claudeAuthManager.signIn()
            await refreshClaude()
            if !isCodexAuthenticated { startAutoRefresh() }
        } catch {
            claudeError = .notAuthenticated
        }
    }

    func signOut() {
        stopAutoRefresh()
        codexAuthManager.signOut()
        codexUsage = nil
        SharedDefaults.clearUsage()
        WidgetCenter.shared.reloadTimelines(ofKind: "AIQuotaWidget")
        // Keep auto-refresh alive if Claude is still signed in
        if isClaudeAuthenticated { startAutoRefresh() }
    }

    func signOutClaude() {
        claudeAuthManager.signOut()
        claudeUsage = nil
        SharedDefaults.clearClaudeUsage()
        WidgetCenter.shared.reloadTimelines(ofKind: "AIQuotaWidget")
        if activeService == .claude { activeService = .codex }
    }

    // MARK: - Settings

    func saveSettings() {
        SharedDefaults.saveSettings(settings)
        if isCodexAuthenticated || isClaudeAuthenticated { startAutoRefresh() }
    }

}
