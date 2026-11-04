// Verbatim production refresh/routing bodies, memory-only dependencies. Never
// constructs the app model, provider coordinators, Keychain or persistent stores.
import Foundation
import SwiftUI
@testable import AIQuotaKit

func check(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: message, code: 1) }
}
@MainActor enum SharedDefaults {
    static var codex: [String: CodexUsage] = [:]
    static var claude: [String: ClaudeUsage] = [:]
    static func saveUsage(_ value: CodexUsage) { codex["primary"] = value }
    static func saveUsage(_ value: CodexUsage, forAccountID id: String) { codex[id] = value }
    static func saveClaudeUsage(_ value: ClaudeUsage) { claude["primary"] = value }
    static func saveClaudeUsage(_ value: ClaudeUsage, forAccountID id: String) { claude[id] = value }
    static func clearClaudeUsage() { claude.removeValue(forKey: "primary") }
    static func clearClaudeUsage(forAccountID id: String) { claude.removeValue(forKey: id) }
}
struct Prefs { var enabled = false; var claudeEnabled = false; var codexEnabled = false }
struct Settings { var notifications = Prefs() }
actor NotificationManager {
    static let shared = NotificationManager()
    func evaluate(claude: ClaudeUsage, prefs: Prefs) {}
    func evaluate(current: CodexUsage, prefs: Prefs) {}
    func notifyPlanChange(service: String, previous: String?, current: String?, enabled: Bool) {}
    func evaluateTopUp(currentBalance: Double, autoReload: CodexAutoReload?, prefs: Prefs) {}
}
struct LogMessage: ExpressibleByStringInterpolation {
    enum Privacy { case `public` }
    init(stringLiteral: String) {}
    init(stringInterpolation: StringInterpolation) {}
    struct StringInterpolation: StringInterpolationProtocol {
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ text: String) {}
        mutating func appendInterpolation<T>(_ value: T) {}
        mutating func appendInterpolation<T>(_ value: T, privacy: Privacy) {}
    }
}
struct Logger { func info(_ message: LogMessage) {}; func warning(_ message: LogMessage) {} }
struct PathMonitor { enum Status { case satisfied }; struct Path { var status = Status.satisfied }; var currentPath = Path() }
actor Client<T: Sendable> {
    var actions: [@Sendable () async throws -> T]
    private(set) var calls = 0
    init(_ actions: [@Sendable () async throws -> T]) { self.actions = actions }
    func fetchUsage() async throws -> T { calls += 1; return try await actions.removeFirst()() }
    func fetchAutoReload() throws -> CodexAutoReload { throw NetworkError.requestFailed }
    func fetchBonusCreditsSpentThisMonth() throws -> Double { throw NetworkError.requestFailed }
    func fetchMemberMonthlyUsage() throws -> CodexMonthlyUsageResponse { throw NetworkError.requestFailed }
}
actor Recovery {
    var state: AuthState = .authenticated
    var restorationFailure: NetworkError?
    var hasRetryableRestoration = false
    func setRetryable() { state = .unauthenticated; hasRetryableRestoration = true }
    func retryTransientRestorationIfNeeded() -> Bool { if hasRetryableRestoration { state = .authenticated; hasRetryableRestoration = false }; return state == .authenticated }
    let recovered: Bool
    private(set) var calls = 0
    init(_ recovered: Bool = true) { self.recovered = recovered }
    func revalidateSessionAfterAuthFailure() -> Bool {
        calls += 1
        if !recovered { state = .unauthenticated }
        return recovered
    }
}
actor Gate<T: Sendable> {
    var continuation: CheckedContinuation<T, Error>?
    var waiting: Bool { continuation != nil }
    func wait() async throws -> T { try await withCheckedThrowingContinuation { continuation = $0 } }
    func finish(_ result: Result<T, Error>) { continuation?.resume(with: result); continuation = nil }
}
@MainActor final class Primary {
    static let isDemoBuild = false
    var isCodexAuthenticated = true, isClaudeAuthenticated = true
    var isCodexLoading = false, isClaudeLoading = false
    var codexRefreshGeneration = 0, claudeRefreshGeneration = 0
    var codexUsage: CodexUsage?, claudeUsage: ClaudeUsage?
    var codexError: NetworkError?, claudeError: NetworkError?
    var codexState: AuthState = .authenticated { didSet { isCodexAuthenticated = codexState == .authenticated } }
    var isCodexRestorationRetryable = false
    var additionalAccounts: [Additional] = []
    // SOURCE_RECOVERY_ACTION
    var codexAutoReload: CodexAutoReload?
    var lastRefreshedAt: Date?
    var codexClient = Client<CodexUsage>([]), claudeClient = Client<ClaudeUsage>([])
    var codexCoordinator = Recovery(), claudeCoordinator = Recovery()
    let logger = Logger(), pathMonitor = PathMonitor(), pathMonitorReady = true, settings = Settings()
    func primaryAccount(for provider: ServiceType) -> ConnectedAccount? {
        ConnectedAccount(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, provider: provider, displayLabel: "Test", authSource: .webSession, connectionKind: .legacyPrimary)
    }
    func refreshTokenHistory() {}
    func clearTokenHistory() {}
    func clearUsageHistory() {}
    func shouldPreserveClaudeLastGood(_ result: ClaudeUsage) -> Bool { false }
    func recordServiceActivityIfNeeded(from: ClaudeUsage?, to: ClaudeUsage) {}
    func recordServiceActivityIfNeeded(from: CodexUsage?, to: CodexUsage) {}
    func isConnectivityError(_ error: Error) -> Bool { error is URLError }
    // SOURCE_CODEX
    // SOURCE_CLAUDE
}
@MainActor final class Additional {
    let provider: ServiceType
    var id: String { account.id }
    var account: ConnectedAccount
    var state: AuthState = .authenticated
    var isAuthenticated: Bool { state == .authenticated }
    var refreshGeneration = 0
    var isLoading = false, isManualRefreshing = false
    var issue: String?, issueError: NetworkError?
    var isCodexRestorationRetryable = false
    func bindIdentity() async -> Bool { true }
    var recoveryAction: AccountRecoveryAction {
        if provider == .codex, state == .unauthenticated, isCodexRestorationRetryable { return .retry }
        return .resolve(authenticated: isAuthenticated, error: issueError, hasIssue: issue != nil)
    }
    var codexUsage: CodexUsage?, claudeUsage: ClaudeUsage?
    var codexClient: Client<CodexUsage>?, claudeClient: Client<ClaudeUsage>?
    var codexCoordinator: Recovery?, claudeCoordinator: Recovery?
    init(_ provider: ServiceType) {
        self.provider = provider
        account = ConnectedAccount(provider: provider, displayLabel: "Test", workspaceID: "scope", authSource: .webSession)
    }
    func clearIssue() { issue = nil; issueError = nil }
    func reportIssue(_ error: Error) { issueError = error as? NetworkError; issue = error.localizedDescription }
    func refreshTokenHistory() {}
    func clearTokenHistory() {}
    func clearUsageHistory() {}
    func adoptState(_ value: AuthState) { state = value; if value == .authenticated || value == .signedOutByUser { isCodexRestorationRetryable = false } }
    // SOURCE_ADDITIONAL
}
typealias QuotaViewModel = Primary
typealias AdditionalAccountSession = Additional
// SOURCE_SETTINGS_STATUS

@MainActor final class Router {
    var routes: [String] = []
    func reconnectAccount(id: String) { routes.append(id) }
    func signIn() { routes.append("primary-codex") }
    func signInClaude() { routes.append("primary-claude") }
    // SOURCE_ROUTE
}
@MainActor final class ScheduledAccount {
    let id: String
    var isAuthenticated = false
    var isCodexRestorationRetryable = true
    init(_ id: String) { self.id = id }
    func signOut() async { isAuthenticated = false; isCodexRestorationRetryable = false }
}
@MainActor final class Scheduler {
    var isCodexAuthenticated = false, isClaudeAuthenticated = false, isCodexRestorationRetryable = false
    var additionalAccounts = [ScheduledAccount("one"), ScheduledAccount("two")]
    var stops = 0
    func stopAutoRefresh() { stops += 1 }
    // SOURCE_SIGNOUT_ACCOUNT
}
// The actual install migration method, with synthetic storage adapters. This
// verifies the missing-marker branch without reading the user's WebKit stores.
@MainActor final class InstallMigration {
    static let freshInstallKey = "app.installedAt.v2"
    var accountStorageID: UUID?
    var sessionTokenKey = "sessionToken"
    @MainActor enum UserDefaults {
        static let standard = Defaults()
        final class Defaults {
            var marker: Any?
            func object(forKey: String) -> Any? { marker }
            func set(_ value: Any?, forKey: String) { marker = value }
        }
    }
    @MainActor enum AuthInstallState {
        static var existing = false
        static func isExistingInstall() async -> Bool { existing }
    }
    @MainActor enum KeychainStore {
        static var saved = true
        static func delete(forKey: String) { saved = false }
    }
    @MainActor enum SharedDefaults {
        static func clearUsage() {}
        static func clearClaudeUsage() {}
    }
    // SOURCE_INSTALL_MIGRATION
}
func codex(_ fetched: Date = Date(timeIntervalSince1970: 100), resetCredits: CodexResetCredits? = nil, accountID: String? = nil) -> CodexUsage {
    CodexUsage(weeklyUsedPercent: 21, weeklyResetAt: fetched, weeklyResetAfterSeconds: 0,
               hourlyUsedPercent: 12, hourlyResetAt: fetched, hourlyResetAfterSeconds: 0,
               hourlyWindowSeconds: 18000, limitReached: false, allowed: true, planType: "pro",
               creditBalance: nil, approxLocalMessages: nil, approxCloudMessages: nil, fetchedAt: fetched,
               reportedWindowShape: .dual, accountID: accountID, resetCredits: resetCredits)
}
func claude(_ fetched: Date = Date(timeIntervalSince1970: 100)) -> ClaudeUsage {
    ClaudeUsage(fiveHourUtilization: 12, fiveHourResetsAt: nil, sevenDayUtilization: 24,
                sevenDayResetsAt: nil, extraUsage: nil, planLabel: .pro, fetchedAt: fetched, quotaScopeID: "scope")
}
@main enum Checks {
    @MainActor static func main() async throws {
        var count = 0
        let scheduler = Scheduler()
        await scheduler.signOutAccount(id: "one")
        try check(scheduler.stops == 0, "signing out one account preserves another Codex retry loop")
        await scheduler.signOutAccount(id: "two")
        try check(scheduler.stops == 1, "signing out the last retryable account stops its loop")
        count += 2
        // Codex renewal must confirm allowance once before clearing Reconnect.
        for recovered in [true, false] {
            let a = Additional(.codex); a.codexUsage = codex()
            a.codexClient = Client([{ throw NetworkError.tokenExpired }, { codex(Date(timeIntervalSince1970: 200)) }])
            a.codexCoordinator = Recovery(recovered)
            await a.refresh()
            try check(a.codexUsage?.fetchedAt == Date(timeIntervalSince1970: recovered ? 200 : 100), "additional Codex retry preserves actual freshness")
            try check(a.recoveryAction == (recovered ? .none : .reconnect), "additional Codex clears stale authentication error only after allowance success")
            try check(await a.codexClient!.calls == (recovered ? 2 : 1), "one additional Codex retry after successful revalidation")
            count += 1
        }
        // Startup UI metadata may have been discarded by a manual refresh. The
        // next primary refresh must reconcile retry eligibility from its owner.
        let recovering = Primary(); recovering.codexState = .unauthenticated
        recovering.isCodexRestorationRetryable = false
        await recovering.codexCoordinator.setRetryable()
        recovering.codexClient = Client([{ codex(Date(timeIntervalSince1970: 200)) }])
        await recovering.refreshCodex()
        try check(recovering.isCodexAuthenticated && recovering.codexError == nil, "primary reconciles a superseded restoration snapshot")
        try check(recovering.codexUsage?.fetchedAt == Date(timeIntervalSince1970: 200), "primary recovery confirms fresh usage")
        count += 1
        for provider in [ServiceType.codex, .claude] {
            for failure in [NetworkError.tokenExpired, .notAuthenticated, .refreshFailed, .networkUnavailable, .httpError(statusCode: 503), .rateLimited] {
                for recovered in [true, false] {
                    let p = Primary(); p.codexUsage = codex(); p.claudeUsage = claude()
                    SharedDefaults.saveUsage(codex()); SharedDefaults.saveClaudeUsage(claude())
                    p.codexCoordinator = Recovery(recovered); p.claudeCoordinator = Recovery(recovered)
                    p.codexClient = Client([{ throw failure }, { throw failure }])
                    p.claudeClient = Client([{ throw failure }, { throw failure }])
                    if provider == .codex { await p.refreshCodex() } else { await p.refreshClaude() }
                    let error = provider == .codex ? p.codexError : p.claudeError
                    try check(AccountRecoveryAction.resolve(authenticated: true, error: error) == (failure.needsReconnect ? .reconnect : .retry), "primary \(provider) recovery")
                    try check(p.codexUsage?.weeklyUsedPercent == 21 && p.claudeUsage?.sevenDayUtilization == 24, "primary saved usage retained")
                    try check(SharedDefaults.codex["primary"] != nil && SharedDefaults.claude["primary"] != nil, "primary saved persistence retained")
                    let a = Additional(provider); a.codexUsage = codex(); a.claudeUsage = claude()
                    a.codexClient = Client([{ throw failure }, { throw failure }]); a.claudeClient = Client([{ throw failure }])
                    a.codexCoordinator = Recovery(recovered); a.claudeCoordinator = Recovery(recovered)
                    await a.refresh()
                    try check(a.recoveryAction == (failure.needsReconnect ? .reconnect : .retry), "additional \(provider) recovery")
                    try check(a.codexUsage != nil && a.claudeUsage != nil, "additional saved usage retained")
                    let coordinator = provider == .codex ? a.codexCoordinator! : a.claudeCoordinator!
                    try check(await coordinator.calls == (failure.isAuthError ? 1 : 0), "only auth failure revalidates")
                    count += 2
                }
            }
            // Successful refresh clears the original typed failure and keeps account-scoped persistence.
            let a = Additional(provider); a.issueError = .tokenExpired; a.issue = "expired"
            a.codexClient = Client([{ codex() }]); a.claudeClient = Client([{ claude() }])
            await a.refresh()
            try check(a.recoveryAction == .none, "success clears recovery")
            try check(provider == .codex ? SharedDefaults.codex[a.id] != nil : SharedDefaults.claude[a.id] != nil, "correct account persistence")
            count += 1
        }
        // Partial responses invalidate optional reset balances even while the
        // primary view keeps the exact last-good windows and their timestamp.
        for retry in [false, true] {
            let p = Primary()
            let old = codex(resetCredits: .init(availableCount: 2), accountID: "workspace-pro")
            p.codexUsage = old; SharedDefaults.saveUsage(old)
            let retained = codex(accountID: "workspace-pro")
            p.codexClient = Client(retry ? [{ throw NetworkError.tokenExpired }, { retained }] : [{ retained }])
            await p.refreshCodex()
            try check(p.codexUsage?.resetCredits == nil && SharedDefaults.codex["primary"]?.resetCredits == nil, "partial primary reset balance remains unknown")
            try check(p.codexUsage?.fetchedAt == old.fetchedAt && p.lastRefreshedAt == nil, "partial response must not relabel old windows as fresh")
            count += 1
        }
        // Revalidation followed by a successful retry updates normally, without sign-in.
        for provider in [ServiceType.codex, .claude] {
            let p = Primary(); p.codexUsage = codex(); p.claudeUsage = claude()
            p.codexClient = Client([{ throw NetworkError.tokenExpired }, { codex(Date(timeIntervalSince1970: 200)) }])
            p.claudeClient = Client([{ throw NetworkError.tokenExpired }, { claude(Date(timeIntervalSince1970: 200)) }])
            if provider == .codex { await p.refreshCodex() } else { await p.refreshClaude() }
            try check((provider == .codex ? p.codexUsage?.fetchedAt : p.claudeUsage?.fetchedAt) == Date(timeIntervalSince1970: 200), "primary retry updates reading")
            try check((provider == .codex ? p.codexError : p.claudeError) == nil, "primary retry clears error")
            // A retry that loses the network remains retryable, even after an auth failure.
            p.codexClient = Client([{ throw NetworkError.tokenExpired }, { throw NetworkError.networkUnavailable }])
            p.claudeClient = Client([{ throw NetworkError.tokenExpired }, { throw URLError(.timedOut) }])
            if provider == .codex { await p.refreshCodex() } else { await p.refreshClaude() }
            try check(AccountRecoveryAction.resolve(authenticated: true, error: provider == .codex ? p.codexError : p.claudeError) == .retry, "primary retry network failure")
            count += 2
        }
        // Primary requests replaced while suspended cannot publish an obsolete error.
        for provider in [ServiceType.codex, .claude] {
            let p = Primary(); p.codexUsage = codex(); p.claudeUsage = claude()
            let cg = Gate<CodexUsage>(), ag = Gate<ClaudeUsage>()
            p.codexClient = Client([{ try await cg.wait() }]); p.claudeClient = Client([{ try await ag.wait() }])
            let task = Task { if provider == .codex { await p.refreshCodex() } else { await p.refreshClaude() } }
            if provider == .codex {
                while !(await cg.waiting) { await Task.yield() }
                p.codexRefreshGeneration += 1
                await cg.finish(.failure(NetworkError.tokenExpired))
            } else {
                while !(await ag.waiting) { await Task.yield() }
                p.claudeRefreshGeneration += 1
                await ag.finish(.failure(NetworkError.tokenExpired))
            }
            await task.value
            try check(p.codexError == nil && p.claudeError == nil, "primary stale error ignored")
            count += 1
        }
        // Identity mismatch must still discard data for only the affected connection.
        for provider in [ServiceType.codex, .claude] {
            let a = Additional(provider); a.codexUsage = codex(); a.claudeUsage = claude()
            a.codexClient = Client([{ throw NetworkError.accountIdentityMismatch }]); a.claudeClient = Client([{ throw NetworkError.accountIdentityMismatch }])
            await a.refresh()
            try check(a.recoveryAction == .reconnect && a.codexUsage == nil, "identity mismatch remains reconnect-only")
            if provider == .claude { try check(a.claudeUsage == nil, "wrong identity data discarded") }
            count += 1
        }
        // Cancellation and replaced generations must not install an obsolete error.
        for cancelled in [true, false] {
            let gate = Gate<CodexUsage>(); let a = Additional(.codex)
            a.codexUsage = codex(); a.codexClient = Client([{ try await gate.wait() }])
            let task = Task { await a.refresh() }
            while !(await gate.waiting) { await Task.yield() }
            if cancelled { task.cancel() } else { a.refreshGeneration += 1 }
            await gate.finish(.failure(NetworkError.tokenExpired)); await task.value
            try check(a.issue == nil && a.codexUsage != nil, "obsolete additional error ignored")
            count += 1
        }
        // A successful late response is also stale after cancellation or replacement.
        for cancelled in [true, false] {
            let gate = Gate<CodexUsage>(); let a = Additional(.codex)
            a.codexUsage = codex(); a.codexClient = Client([{ try await gate.wait() }])
            let task = Task { await a.refresh() }
            while !(await gate.waiting) { await Task.yield() }
            if cancelled { task.cancel() } else { a.refreshGeneration += 1 }
            await gate.finish(.success(codex(Date(timeIntervalSince1970: 200)))); await task.value
            try check(a.codexUsage?.fetchedAt == Date(timeIntervalSince1970: 100), "obsolete additional success must not publish freshness")
            count += 1
        }
        for provider in [ServiceType.codex, .claude] {
            for kind in [AccountConnectionKind.legacyPrimary, .isolated] {
                let model = Primary(), additional = Additional(provider)
                let account = ConnectedAccount(provider: provider, displayLabel: "Fixture", authSource: .webSession, connectionKind: kind)
                additional.account = account
                // Settings resolves the selected account by its persisted ID.
                let selected = kind == .isolated ? additional.account : account
                model.additionalAccounts = [additional]
                for connected in [false, true] {
                    for failure: NetworkError? in [nil, .tokenExpired, .networkUnavailable] {
                        model.codexState = connected ? .authenticated : .unauthenticated
                        model.isClaudeAuthenticated = connected
                        model.codexError = failure; model.claudeError = failure
                        additional.state = connected ? .authenticated : .unauthenticated
                        additional.issueError = failure; additional.issue = failure?.localizedDescription
                        let status = AccountConnectionStatus(account: selected, viewModel: model)
                        try check(status.needsReconnect == (!connected || failure?.needsReconnect == true), "Settings uses same typed reconnect rule for every account")
                        count += 1
                    }
                }
                if provider == .codex {
                    model.codexState = .unauthenticated; model.isCodexRestorationRetryable = true
                    additional.state = .unauthenticated; additional.isCodexRestorationRetryable = true
                    let status = AccountConnectionStatus(account: selected, viewModel: model)
                    try check(!status.needsReconnect, "Settings temporary restoration remains noninteractive")
                    count += 1
                }
            }
        }
        for scoped in [false, true] {
            for marker in [false, true] {
                for existing in [false, true] {
                    InstallMigration.UserDefaults.standard.marker = marker ? true : nil
                    InstallMigration.AuthInstallState.existing = existing
                    InstallMigration.KeychainStore.saved = true
                    let migration = InstallMigration()
                    migration.accountStorageID = scoped ? UUID() : nil
                    await migration.clearStateIfFreshInstall()
                    try check(InstallMigration.KeychainStore.saved, "install marker migration must preserve saved auth (scoped: \(scoped), marker: \(marker), existing: \(existing))")
                    count += 1
                }
            }
        }
        let router = Router()
        var expectedRoutes: [String] = []
        for provider in [ServiceType.codex, .claude] {
            for kind in [AccountConnectionKind.legacyPrimary, .isolated] {
                let a = ConnectedAccount(provider: provider, displayLabel: "Test", authSource: .webSession, connectionKind: kind)
                expectedRoutes.append(kind == .isolated ? a.id : "primary-\(provider)")
                await router.reconnect(a)
            }
        }
        try check(router.routes == expectedRoutes, "exact selected account sign-in routes, including missing isolated session")
        print("PASS: \(count + 4) source-body recovery/routing scenarios; cached usage, typed errors, cancellation, no live stores or sign-in")
    }
}
