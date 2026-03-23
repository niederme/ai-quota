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

    // MARK: - Onboarding

    /// True if the user has never completed the onboarding wizard.
    var shouldShowOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: "onboarding.v1.hasCompleted")
            && !onboardingTriggeredThisSession
    }

    /// Set to true after the window has been opened once per session,
    /// so clicking the menu bar icon repeatedly doesn't re-open it.
    private(set) var onboardingTriggeredThisSession = false

    func markOnboardingTriggered() {
        onboardingTriggeredThisSession = true
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding.v1.hasCompleted")
        onboardingTriggeredThisSession = true
    }

    func resetOnboardingForReplay() {
        // Called from Settings "Guided Setup…" button — lets the user re-run
        // the wizard without wiping any auth or settings state.
        onboardingTriggeredThisSession = false
    }

    /// Full reset: signs out all services, clears cached data, resets settings
    /// and onboarding state — the app behaves exactly like a fresh install.
    func resetToNewUser() {
        signOut()
        signOutClaude()
        settings = .default
        saveSettings()
        UserDefaults.standard.removeObject(forKey: "onboarding.v1.hasCompleted")
        onboardingTriggeredThisSession = false
    }

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
    /// Incremented on each manual refresh so the previous task's `defer` doesn't
    /// clear `isLoading` after the new request has already started.
    private var codexRefreshGeneration = 0
    private var claudeRefreshGeneration = 0

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

        // Bridge ObservableObject → @Observable.
        // Also kick off auto-refresh when auth is first restored from Keychain — the
        // Keychain load is deferred by one run loop tick (to keep the app window first
        // in front of any OS "allow keychain" dialog), so isAuthenticated is always
        // false at init time and must be handled reactively here instead.
        authCancellable = codexAuth.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                isCodexAuthenticated = value
                if value && refreshTask == nil { startAutoRefresh() }
            }

        claudeAuthCancellable = claudeAuth.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                isClaudeAuthenticated = value
                // Default active service to Claude if that's all that's authenticated
                if value && !isCodexAuthenticated { activeService = .claude }
                if value && refreshTask == nil { startAutoRefresh() }
            }

        // Request notification permission on launch
        if settings.notifications.enabled {
            Task { await NotificationManager.shared.requestPermission() }
        }

        // Start path monitor first so currentPath is valid before the first fetch
        startPathMonitor()

        // Warm up WKWebView's XPC service immediately — the first getAllCookies call
        // takes up to 20 seconds on a cold process. Firing it here means the service
        // is already running by the time silentSignInIfPossible() or syncCookies()
        // is needed, whether or not Claude is currently authenticated.
        Task { await claudeAuthManager.syncCookies() }
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
                    if self.wasOffline {
                        // Came back online — fire an immediate refresh.
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
        // Run both fetches concurrently, then reload widgets once both are done
        // so they always get a consistent snapshot.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshCodex() }
            group.addTask { await self.refreshClaude() }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refreshCodex() async {
        if !isCodexAuthenticated {
            guard await codexAuthManager.silentSignInIfPossible() else { return }
        }
        guard !isCodexLoading else { return }
        let gen = codexRefreshGeneration
        isCodexLoading = true
        codexError = nil
        defer { if codexRefreshGeneration == gen { isCodexLoading = false } }

        do {
            let result = try await codexClient.fetchUsage()
            codexUsage = result
            lastRefreshedAt = .now
            SharedDefaults.saveUsage(result)
            await NotificationManager.shared.evaluate(current: result, prefs: settings.notifications)
        } catch let e as NetworkError {
            if e.isAuthError {
                codexUsage = nil
                SharedDefaults.clearUsage()
                // Session may have expired — try a forced cookie recheck before clearing
                // auth state. Avoids a brief "Connect" flash when cookies are still valid
                // but haven't been synced to URLSession yet.
                if await codexAuthManager.silentSignInIfPossible(forceRecheck: true) {
                    await refreshCodex()
                    return
                }
                // Recheck also failed — session is genuinely gone.
                codexAuthManager.isAuthenticated = false
                // Don't surface an error banner; the user can reconnect from the gauge.
                return
            } else if case .networkUnavailable = e, !pathMonitorReady {
                // Path monitor hasn't settled yet — suppress the banner to avoid
                // the false-positive "No network connection" flash at launch.
                logger.info("[CodexRefresh] suppressing networkUnavailable: pathMonitor not ready yet")
                return
            } else if case .decodingError = e {
                // Transient decode failure (e.g. server returned an error page during
                // post-reboot network init). Let the next auto-refresh recover silently.
                logger.info("[CodexRefresh] suppressing decodingError — will retry on next cycle")
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
        if !isClaudeAuthenticated {
            guard await claudeAuthManager.silentSignInIfPossible() else { return }
        }
        guard !isClaudeLoading else { return }
        let gen = claudeRefreshGeneration
        isClaudeLoading = true
        claudeError = nil
        defer { if claudeRefreshGeneration == gen { isClaudeLoading = false } }

        do {
            let result = try await claudeClient.fetchUsage()
            claudeUsage = result
            lastRefreshedAt = .now
            SharedDefaults.saveClaudeUsage(result)
            await NotificationManager.shared.evaluate(claude: result, prefs: settings.notifications)
        } catch let e as NetworkError {
            if e.isAuthError {
                claudeUsage = nil
                SharedDefaults.clearClaudeUsage()
                // Session may have expired — sync fresh cookies and retry the fetch
                // once. Using a direct retry (not recursion) avoids an infinite loop
                // if the session is genuinely invalid.
                guard await claudeAuthManager.silentSignInIfPossible(forceRecheck: true) else {
                    claudeAuthManager.isAuthenticated = false
                    return
                }
                do {
                    let result = try await claudeClient.fetchUsage()
                    claudeUsage = result
                    lastRefreshedAt = .now
                    SharedDefaults.saveClaudeUsage(result)
                    await NotificationManager.shared.evaluate(claude: result, prefs: settings.notifications)
                } catch {
                    // Retry also failed — session is genuinely gone.
                    claudeAuthManager.isAuthenticated = false
                }
                return
            } else if case .networkUnavailable = e, !pathMonitorReady {
                // Path monitor hasn't settled yet — suppress the banner to avoid
                // the false-positive "No network connection" flash at launch.
                logger.info("[ClaudeRefresh] suppressing networkUnavailable: pathMonitor not ready yet")
                return
            } else if case .decodingError = e {
                // Transient decode failure (e.g. server returned an error page during
                // post-reboot network init). Let the next auto-refresh recover silently.
                logger.info("[ClaudeRefresh] suppressing decodingError — will retry on next cycle")
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
        if settings.notifications.enabled {
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

    /// User-initiated refresh. Cancels any in-flight auto-refresh and restarts
    /// immediately, bypassing the `isLoading` guard that blocks concurrent calls.
    func manualRefresh() {
        codexRefreshGeneration += 1
        claudeRefreshGeneration += 1
        isCodexLoading = false
        isClaudeLoading = false
        startAutoRefresh()
    }

    // MARK: - Sign In / Out

    func signIn() async {
        do {
            try await codexAuthManager.signIn()
            await refreshCodex()
            // Only start auto-refresh if not already running — restarting it cancels
            // any in-progress Claude fetch and can leave isClaudeLoading permanently true.
            if refreshTask == nil { startAutoRefresh() }
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
            if refreshTask == nil { startAutoRefresh() }
            return
        }
        do {
            try await claudeAuthManager.signIn()
            await refreshClaude()
            if refreshTask == nil { startAutoRefresh() }
        } catch {
            claudeError = .notAuthenticated
        }
    }

    func signOut() {
        stopAutoRefresh()
        codexAuthManager.signOut()
        codexUsage = nil
        SharedDefaults.clearUsage()
        WidgetCenter.shared.reloadAllTimelines()
        // Keep auto-refresh alive if Claude is still signed in
        if isClaudeAuthenticated { startAutoRefresh() }
    }

    func signOutClaude() {
        claudeAuthManager.signOut()
        claudeUsage = nil
        SharedDefaults.clearClaudeUsage()
        WidgetCenter.shared.reloadAllTimelines()
        if activeService == .claude { activeService = .codex }
    }

    // MARK: - Settings

    func saveSettings() {
        SharedDefaults.saveSettings(settings)
        if isCodexAuthenticated || isClaudeAuthenticated { startAutoRefresh() }
    }

}
