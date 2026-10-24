import Foundation

/// Only new successful identity-checked fetches enter this store. It never reads
/// or rewrites cached usage, analytics, credentials, or the user's past history.
public actor QuotaInsightStore {
    // App-only insights use their own preference key; they are not widget data.
    // Keep test clients away from the user's production insight store as well.
    public static let shared = QuotaInsightStore(suiteName:
        Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
            ? "QuotaInsightTests.clients.\(ProcessInfo.processInfo.processIdentifier)" : nil)
    private static let key = "quotaPaceObservations.v1"
    private let defaults: UserDefaults
    private let accountLookup: @Sendable (String) -> ConnectedAccount?
    private var generation = 0
    private struct Entry: Codable {
        var scope: QuotaForecastScope
        var observations: [QuotaPaceObservation]
        var dismissed: Bool = false
    }
    private var entries: [Entry]

    public init(suiteName: String? = nil,
                accountLookup: @escaping @Sendable (String) -> ConnectedAccount? = { AccountRegistry.account(id: $0) }) {
        self.accountLookup = accountLookup
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.defaults = defaults
        entries = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    public func captureGeneration() -> Int { generation }

    public func clear() {
        generation += 1
        entries.removeAll()
        defaults.removeObject(forKey: Self.key)
    }

    public func remove(accountID: String) {
        generation += 1
        entries.removeAll { $0.scope.accountID == accountID }
        save()
    }

    private func isCurrent(_ account: ConnectedAccount, identity: String, captureGeneration: Int?) -> Bool {
        guard captureGeneration == nil || captureGeneration == generation,
              let current = accountLookup(account.id), current.provider == account.provider,
              current.workspaceID == identity else { return false }
        return true
    }

    public func record(_ observation: QuotaPaceObservation, now: Date = .now) {
        guard observation.valid, observation.date <= now,
              now.timeIntervalSince(observation.date) <= observation.scope.window.freshness else { return }
        entries.removeAll { $0.scope.resetAt <= now }
        let scope = observation.scope
        if let index = entries.firstIndex(where: { $0.scope == scope }) {
            var samples = entries[index].observations
            if let last = samples.last {
                guard observation.date > last.date else { return }
                // A correction starts a fresh regime. Keep the dismissal for this
                // window even when rate or capacity changes.
                if observation.used < last.used || observation.limit != last.limit {
                    samples.removeAll()
                } else {
                    let spacing: TimeInterval = switch scope.window {
                    case .fiveHour: 5 * 60
                    case .weekly: 15 * 60
                    case .monthly: 30 * 60
                    }
                    guard observation.date.timeIntervalSince(last.date) >= spacing else { return }
                }
            }
            samples.removeAll { $0.date < observation.date.addingTimeInterval(-scope.window.lookback) }
            samples.append(observation)
            entries[index].observations = Array(samples.suffix(400))
        } else {
            // Bound persistence; no build/database dependency or account history migration.
            let dismissed = entries.contains {
                $0.dismissed && $0.scope.accountID == scope.accountID && $0.scope.provider == scope.provider
                    && $0.scope.identity == scope.identity && $0.scope.window == scope.window
                    && $0.scope.resetAt == scope.resetAt
            }
            entries.append(Entry(scope: scope, observations: [observation], dismissed: dismissed))
            if entries.count > 128 { entries.removeFirst(entries.count - 128) }
        }
        save()
    }

    public func forecasts(accountID: String, provider: String, identity: String,
                          source: String, plan: String, now: Date = .now) -> [QuotaExhaustionForecast] {
        entries.filter {
            !$0.dismissed && $0.scope.accountID == accountID && $0.scope.provider == provider
                && $0.scope.identity == identity && $0.scope.source == source && $0.scope.plan == plan
        }.compactMap {
            QuotaExhaustionForecast.estimate(scope: $0.scope, observations: $0.observations, now: now)
        }.sorted { $0.earliest < $1.earliest }
    }

    public func dismiss(_ scope: QuotaForecastScope) {
        // All plan/source variants of this account's same provider window are
        // dismissed together. A changing estimate cannot turn the banner back on.
        for index in entries.indices where entries[index].scope.accountID == scope.accountID
            && entries[index].scope.provider == scope.provider
            && entries[index].scope.identity == scope.identity
            && entries[index].scope.window == scope.window
            && entries[index].scope.resetAt == scope.resetAt {
            entries[index].dismissed = true
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func recordClaude(_ usage: ClaudeUsage, account: ConnectedAccount, identity: String,
                             now: Date = .now, captureGeneration: Int? = nil) {
        guard isCurrent(account, identity: identity, captureGeneration: captureGeneration),
              account.provider == .claude, account.workspaceID == identity,
              !identity.isEmpty, usage.quotaScopeID == identity,
              usage.source == .web, usage.planLabel != .unknown else { return }
        for (window, used, reset) in [
            (QuotaForecastScope.Window.fiveHour, usage.fiveHourUtilization, usage.fiveHourResetsAt),
            (.weekly, usage.sevenDayUtilization, usage.sevenDayResetsAt)
        ] {
            guard let used, let reset else { continue }
            let scope = QuotaForecastScope(accountID: account.id, provider: "claude", identity: identity,
                source: usage.source.rawValue, plan: usage.planLabel.rawValue, window: window, resetAt: reset)
            record(QuotaPaceObservation(scope: scope, date: usage.fetchedAt, used: used), now: now)
        }
        // Claude spend limits have no actual reset metadata in the current API
        // model. Never infer a monthly window from the current calendar month.
    }

    public func recordCodex(_ usage: CodexUsage, account: ConnectedAccount, identity: String,
                            now: Date = .now, captureGeneration: Int? = nil) {
        guard isCurrent(account, identity: identity, captureGeneration: captureGeneration),
              account.provider == .codex, account.workspaceID == identity, !identity.isEmpty,
              usage.accountID == identity, let source = usage.quotaSource, source != .unknown,
              !usage.planType.isEmpty, usage.planType.lowercased() != "unknown" else { return }
        func append(_ window: QuotaForecastScope.Window, used: Double, limit: Double = 100, reset: Date) {
            let scope = QuotaForecastScope(accountID: account.id, provider: "codex", identity: identity,
                source: source.rawValue, plan: usage.planType, window: window, resetAt: reset)
            record(.init(scope: scope, date: usage.fetchedAt, used: used, limit: limit), now: now)
        }
        if usage.reportedWindowShape == .dual, usage.hourlyWindowSeconds == 18000 {
            append(.fiveHour, used: Double(usage.hourlyUsedPercent), reset: usage.hourlyResetAt)
        }
        if usage.reportedWindowShape != nil {
            append(.weekly, used: Double(usage.weeklyUsedPercent), reset: usage.weeklyResetAt)
        } else if let budget = usage.displayableMonthlyBudget,
                  let used = budget.used, let limit = budget.limit, let reset = budget.resetAt {
            append(.monthly, used: used, limit: limit, reset: reset)
        }
    }

}
