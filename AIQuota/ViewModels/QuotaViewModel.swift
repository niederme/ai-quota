import Foundation
import AppKit
import CoreGraphics
import Network
import os
import AIQuotaKit
import WidgetKit

@MainActor
@Observable
final class QuotaViewModel {

    private let logger = Logger(subsystem: "ai.quota", category: "refresh")

    // MARK: - Codex (OpenAI)

    var codexUsage: CodexUsage?
    var isCodexLoading = false
    var codexError: NetworkError?

    let codexCoordinator: CodexAuthCoordinator
    private let codexClient: OpenAIClient

    // MARK: - Claude

    var claudeUsage: ClaudeUsage?
    var isClaudeLoading = false
    var claudeError: NetworkError?

    let claudeCoordinator: ClaudeAuthCoordinator
    private let claudeClient: ClaudeClient

    // MARK: - Auth state (derived from coordinator streams)

    var claudeState: AuthState = .unknown
    var codexState:  AuthState = .unknown

    var isClaudeAuthenticated: Bool { claudeState == .authenticated }
    var isCodexAuthenticated:  Bool { codexState  == .authenticated }
    var isRestoringSession: Bool {
        claudeState == .unknown || claudeState == .restoringSession ||
        codexState  == .unknown || codexState  == .restoringSession
    }

    private let resetCoordinator: AppResetCoordinator

    // MARK: - Shared state

    var settings: AppSettings = SharedDefaults.loadSettings()
    /// Which service's panel is visible in the popover.
    var activeService: ServiceType = .codex

    // MARK: - Enrollment

    /// Persisted in SharedDefaults (app-group) so the widget can read it.
    /// Populated from first successful sign-in; cleared only on explicit Sign Out or reset.
    var enrolledServices: Set<ServiceType> = SharedDefaults.loadEnrolledServices()

    var isCodexEnrolled: Bool { enrolledServices.contains(.codex) }
    var isClaudeEnrolled: Bool { enrolledServices.contains(.claude) }

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
        Task {
            await AnalyticsClient.shared.send("onboarding_completed", enabled: settings.analyticsEnabled)
        }
    }

    func recordDailyActiveIfNeeded() {
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let key = "analytics.lastActiveDate"
        guard UserDefaults.standard.string(forKey: key) != today else { return }
        UserDefaults.standard.set(today, forKey: key)
        let enabled = settings.analyticsEnabled
        Task {
            await AnalyticsClient.shared.send("app_active", enabled: enabled)
        }
    }

    func resetOnboardingForReplay() {
        // Called from Settings "Guided Setup…" button — lets the user re-run
        // the wizard without wiping any auth or settings state.
        onboardingTriggeredThisSession = false
    }

    /// Full reset: signs out all services, clears cached data, resets settings
    /// and onboarding state — the app behaves exactly like a fresh install.
    func resetToNewUser() async {
        // Step 1: stop refresh and await quiescence.
        // Capture the task reference *before* stopAutoRefresh() sets refreshTask = nil,
        // otherwise the await below is always a no-op.
        let inFlight = refreshTask
        stopAutoRefresh()
        await inFlight?.value  // actually suspends until the in-flight refresh completes

        // Step 2: auth reset
        let result = await resetCoordinator.reset()
        if !result.warnings.isEmpty {
            logger.warning("[Reset] warnings: \(result.warnings.joined(separator: "; "))")
        }

        // Step 3: product state reset (only after auth reset completes)
        claudeUsage = nil
        codexUsage  = nil
        SharedDefaults.clearUsage()
        SharedDefaults.clearClaudeUsage()
        settings = .default
        // Persist settings directly — calling saveSettings() would invoke startAutoRefresh(),
        // which must not fire while the auth coordinators are still in the resetting state.
        SharedDefaults.saveSettings(settings)
        enrolledServices = []
        SharedDefaults.clearEnrolledServices()
        UserDefaults.standard.removeObject(forKey: "onboarding.v1.hasCompleted")
        onboardingTriggeredThisSession = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Backward-compatible aliases (used by MenuBarIconView / AIQuotaApp)

    var usage: CodexUsage? { codexUsage }
    var isLoading: Bool { isCodexLoading || isClaudeLoading }
    var error: NetworkError? {
        get { codexError }
        set { codexError = newValue }
    }
    var isAuthenticated: Bool { isCodexAuthenticated }

    // MARK: - Last refreshed

    var lastRefreshedAt: Date?

    // MARK: - Private

    private var refreshTask: Task<Void, Never>?
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
    private var appIsActive = false
    private var appLifecycleObservers: [NSObjectProtocol] = []
    private var workspaceLifecycleObservers: [NSObjectProtocol] = []

    // MARK: - Init

    init() {
        let claude = ClaudeAuthCoordinator()
        let codex  = CodexAuthCoordinator()

        self.claudeCoordinator = claude
        self.codexCoordinator  = codex
        self.claudeClient      = ClaudeClient(coordinator: claude)
        self.codexClient       = OpenAIClient(coordinator: codex)
        self.resetCoordinator  = AppResetCoordinator(claude: claude, codex: codex)

        // Load cached data immediately
        codexUsage  = SharedDefaults.loadCachedUsage()
        claudeUsage = SharedDefaults.loadCachedClaudeUsage()

        // Normalise any mixed per-threshold notification state from pre-consolidation builds.
        // OR-resolves each group (any=true → all-true) so aggregate toggles always see
        // a clean on/off state from the first render.
        let preNorm = settings
        settings.notifications.normalizeThresholds()
        if settings != preNorm { SharedDefaults.saveSettings(settings) }

        // Observe coordinator state streams and drive UI state + auto-refresh.
        Task { [weak self] in
            guard let self else { return }
            for await state in claudeCoordinator.stateStream {
                await MainActor.run {
                    self.claudeState = state
                    // Auto-enroll on first successful auth (handles migration from pre-enrollment builds)
                    if state == .authenticated && !self.enrolledServices.contains(.claude) {
                        self.enrolledServices.insert(.claude)
                        SharedDefaults.enrollService(.claude)
                    }
                    if state == .authenticated && self.refreshTask == nil {
                        self.startAutoRefresh()
                    }
                    if state == .unauthenticated || state == .signedOutByUser {
                        self.claudeUsage = nil
                        SharedDefaults.clearClaudeUsage()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
            }
        }
        Task { [weak self] in
            guard let self else { return }
            for await state in codexCoordinator.stateStream {
                await MainActor.run {
                    self.codexState = state
                    if state == .authenticated && !self.enrolledServices.contains(.codex) {
                        self.enrolledServices.insert(.codex)
                        SharedDefaults.enrollService(.codex)
                        Task {
                            await AnalyticsClient.shared.send(
                                "service_connected",
                                params: ["service_name": "codex"],
                                enabled: self.settings.analyticsEnabled
                            )
                        }
                    }
                    if state == .authenticated && self.refreshTask == nil {
                        self.startAutoRefresh()
                    }
                    if state == .unauthenticated || state == .signedOutByUser {
                        self.codexUsage = nil
                        SharedDefaults.clearUsage()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
            }
        }

        // Request notification permission on launch
        if settings.notifications.enabled {
            Task { await NotificationManager.shared.requestPermission() }
        }

        // Start path monitor first so currentPath is valid before the first fetch
        startPathMonitor()
        startLifecycleObservers()

        // Bootstrap both coordinators — handles Keychain / WKWebView session restore
        // internally; no need for a deferred Keychain access pattern here.
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.claudeCoordinator.bootstrap() }
                group.addTask { await self.codexCoordinator.bootstrap() }
            }
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
                    if self.wasOffline {
                        // Came back online — resume the loop with a fresh fetch so
                        // Auto mode can ramp back up immediately.
                        self.wasOffline = false
                        self.restartAutoRefresh(immediateRefresh: true)
                    }
                } else {
                    self.wasOffline = true
                    self.restartAutoRefresh(immediateRefresh: false)
                }
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func startLifecycleObservers() {
        appIsActive = NSApplication.shared.isActive

        let notificationCenter = NotificationCenter.default
        appLifecycleObservers.append(
            notificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.appIsActive = true
                    self.restartAutoRefresh(immediateRefresh: true)
                }
            }
        )
        appLifecycleObservers.append(
            notificationCenter.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.appIsActive = false
                    self.restartAutoRefresh(immediateRefresh: false)
                }
            }
        )
        appLifecycleObservers.append(
            notificationCenter.addObserver(
                forName: .NSProcessInfoPowerStateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let shouldRefreshNow = !ProcessInfo.processInfo.isLowPowerModeEnabled
                    self.restartAutoRefresh(immediateRefresh: shouldRefreshNow)
                }
            }
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceLifecycleObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.restartAutoRefresh(immediateRefresh: true)
                }
            }
        )
        workspaceLifecycleObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.restartAutoRefresh(immediateRefresh: false)
                }
            }
        )
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
        guard isCodexAuthenticated else { return }
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
                // Session may have expired — try a forced revalidation before clearing
                // auth state. Avoids a brief "Connect" flash when cookies are still valid.
                guard await codexCoordinator.revalidateSessionAfterAuthFailure() else { return }
                // Retry once after successful revalidation
                do {
                    let result = try await codexClient.fetchUsage()
                    codexUsage = result
                    lastRefreshedAt = .now
                    SharedDefaults.saveUsage(result)
                    await NotificationManager.shared.evaluate(current: result, prefs: settings.notifications)
                } catch {
                    // Retry also failed — coordinator already transitioned to unauthenticated
                }
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
        guard isClaudeAuthenticated else { return }
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
                guard await claudeCoordinator.revalidateSessionAfterAuthFailure() else { return }
                do {
                    let result = try await claudeClient.fetchUsage()
                    claudeUsage = result
                    lastRefreshedAt = .now
                    SharedDefaults.saveClaudeUsage(result)
                    await NotificationManager.shared.evaluate(claude: result, prefs: settings.notifications)
                } catch {
                    // Retry also failed — coordinator already transitioned to unauthenticated
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

    func startAutoRefresh(immediateRefresh: Bool = true) {
        if settings.notifications.enabled {
            Task { await NotificationManager.shared.requestPermission() }
        }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            if immediateRefresh {
                await refresh()
            }
            while !Task.isCancelled {
                let sleepInterval = self.nextRefreshInterval()
                try? await Task.sleep(for: .seconds(sleepInterval))
                guard !Task.isCancelled else { break }
                await self.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func restartAutoRefresh(immediateRefresh: Bool) {
        guard isCodexAuthenticated || isClaudeAuthenticated else { return }
        startAutoRefresh(immediateRefresh: immediateRefresh)
    }

    private func nextRefreshInterval() -> TimeInterval {
        if let fixedRefreshInterval = settings.fixedRefreshInterval {
            return fixedRefreshInterval
        }

        return AutoRefreshPolicy.interval(for: autoRefreshContext())
    }

    private func autoRefreshContext() -> AutoRefreshContext {
        AutoRefreshContext(
            appIsActive: appIsActive,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            networkAvailable: !pathMonitorReady || pathMonitor.currentPath.status == .satisfied,
            machineIdleSeconds: CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: .null
            ),
            hasCachedUsageData: codexUsage != nil || claudeUsage != nil,
            codexNearThreshold: isCodexNearThreshold,
            claudeNearThreshold: isClaudeNearThreshold
        )
    }

    private var isCodexNearThreshold: Bool {
        guard let codexUsage else { return false }
        return codexUsage.limitReached
            || codexUsage.hourlyUsedPercent >= 85
            || codexUsage.weeklyUsedPercent >= 85
            || codexUsage.hourlyResetAfterSeconds <= 900
            || codexUsage.weeklyResetAfterSeconds <= 900
    }

    private var isClaudeNearThreshold: Bool {
        guard let claudeUsage else { return false }
        return claudeUsage.limitReached
            || claudeUsage.usedPercent >= 85
            || claudeUsage.sevenDayUtilization >= 85
            || claudeUsage.resetAfterSeconds <= 900
            || claudeUsage.sevenDayResetAfterSeconds <= 900
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
            try await codexCoordinator.signIn()
            await refreshCodex()
            if refreshTask == nil { startAutoRefresh() }
        } catch {
            codexError = .notAuthenticated
        }
    }

    func signInClaude() async {
        do {
            try await claudeCoordinator.signIn()
            // Propagate auth state synchronously before refreshClaude() checks isClaudeAuthenticated.
            // The stateStream observer will also fire, but may lag behind by one async hop.
            claudeState = .authenticated
            // Mirror the stream-observer enrollment so isClaudeEnrolled is true before the refresh.
            if !enrolledServices.contains(.claude) {
                enrolledServices.insert(.claude)
                SharedDefaults.enrollService(.claude)
                Task {
                    await AnalyticsClient.shared.send(
                        "service_connected",
                        params: ["service_name": "claude"],
                        enabled: settings.analyticsEnabled
                    )
                }
            }
            await refreshClaude()
            if refreshTask == nil { startAutoRefresh() }
        } catch {
            claudeError = .notAuthenticated
        }
    }

    func signOut() {
        stopAutoRefresh()
        Task {
            try? await codexCoordinator.signOut()
            self.enrolledServices.remove(.codex)
            SharedDefaults.unenrollService(.codex)
            // If menuBarService is now unenrolled, correct it
            if !self.enrolledServices.contains(self.settings.menuBarService),
               let fallback = self.enrolledServices.first {
                self.settings.menuBarService = fallback
                self.saveSettings()
            }
            // Refresh loop was stopped above; it will restart on next sign-in or manual refresh.
        }
    }

    func signOutClaude() {
        Task {
            try? await claudeCoordinator.signOut()
            self.enrolledServices.remove(.claude)
            SharedDefaults.unenrollService(.claude)
            if !self.enrolledServices.contains(self.settings.menuBarService),
               let fallback = self.enrolledServices.first {
                self.settings.menuBarService = fallback
                self.saveSettings()
            }
            if activeService == .claude { activeService = .codex }
        }
    }

    // MARK: - Settings

    func saveSettings() {
        SharedDefaults.saveSettings(settings)
        if isCodexAuthenticated || isClaudeAuthenticated { startAutoRefresh() }
    }

}

// MARK: - Demo support

#if DEMO_MODE
extension QuotaViewModel {
    /// Puts the view model into a stable authenticated-but-empty state
    /// without touching the real auth or network layer.
    func prepareForDemo() {
        stopAutoRefresh()
        claudeState      = .authenticated
        codexState       = .authenticated
        enrolledServices = [.claude, .codex]
        claudeUsage      = nil
        codexUsage       = nil
        claudeError      = nil
        codexError       = nil
        isClaudeLoading  = true
        isCodexLoading   = true
        lastRefreshedAt  = nil
    }

    /// Pushes a scripted frame of fake usage data into the view model.
    func applyDemoFrame(
        claude: ClaudeUsage?,
        codex: CodexUsage?,
        claudeLoading: Bool = false,
        codexLoading: Bool = false
    ) {
        claudeUsage     = claude
        codexUsage      = codex
        isClaudeLoading = claudeLoading
        isCodexLoading  = codexLoading
        lastRefreshedAt = claude != nil || codex != nil ? .now : nil
    }
}
#endif
