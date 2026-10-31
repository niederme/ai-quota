import Foundation

/// Device-local observations from successful requests. Cached readings never enter this history.
public struct QuotaForecastHistory: Codable, Sendable {
    struct Entry: Codable, Sendable {
        let scope: QuotaForecastScope
        var observations: [QuotaPaceObservation]
        var dismissed = false
    }
    var entries: [Entry] = []
    public init() {}

    public static func observations(for reading: QuotaReading, accountID: String,
                                    provider: String) -> [QuotaPaceObservation] {
        guard let identity = reading.providerIdentity, !identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let plan = reading.metadata?.plan, !plan.isEmpty, plan.lowercased() != "unknown",
              provider == "codex" || provider == "claude" else { return [] }
        let source = provider == "codex" ? "wham" : "oauth"
        func sample(_ window: QuotaForecastScope.Window, used: Double, limit: Double = 100,
                    reset: Date) -> QuotaPaceObservation {
            .init(scope: .init(accountID: accountID, provider: provider, identity: identity,
                              source: source, plan: plan, window: window, resetAt: reset),
                  date: reading.fetchedAt, used: used, limit: limit)
        }
        var result = reading.windows.compactMap { value -> QuotaPaceObservation? in
            guard let reset = value.resetsAt else { return nil }
            let window: QuotaForecastScope.Window
            switch value.durationSeconds {
            case 18000: window = .fiveHour
            case 604800: window = .weekly
            case 28 * 86400...31 * 86400: window = .monthly
            default: return nil
            }
            return sample(window, used: value.usedPercent, reset: reset)
        }
        if let budget = reading.budgetOnly, let reset = budget.resetsAt {
            result.append(sample(.monthly, used: budget.used, limit: budget.limit, reset: reset))
        }
        return result.filter(\.valid)
    }

    public mutating func record(_ reading: QuotaReading, accountID: String, provider: String, now: Date = .now) {
        let samples = Self.observations(for: reading, accountID: accountID, provider: provider)
        entries.removeAll { $0.scope.resetAt <= now }
        for sample in samples {
            guard sample.date <= now, now.timeIntervalSince(sample.date) <= sample.scope.window.freshness else { continue }
            // Reconnecting a profile to another identity starts a new history.
            entries.removeAll { $0.scope.accountID == accountID && $0.scope.provider == provider
                && $0.scope.identity != sample.scope.identity }
            if let index = entries.firstIndex(where: { $0.scope == sample.scope }) {
                var observations = entries[index].observations
                if let last = observations.last {
                    guard sample.date > last.date else { continue }
                    if sample.used < last.used || sample.limit != last.limit {
                        observations.removeAll()
                    } else {
                        let spacing: TimeInterval = switch sample.scope.window {
                        case .fiveHour: 300
                        case .weekly: 900
                        case .monthly: 1800
                        }
                        guard sample.date.timeIntervalSince(last.date) >= spacing else { continue }
                    }
                }
                observations.removeAll { $0.date < sample.date.addingTimeInterval(-sample.scope.window.lookback) }
                observations.append(sample)
                entries[index].observations = Array(observations.suffix(400))
            } else {
                let dismissed = entries.contains { $0.dismissed && Self.sameWindow($0.scope, sample.scope) }
                entries.append(.init(scope: sample.scope, observations: [sample], dismissed: dismissed))
            }
        }
        entries = Array(entries.suffix(24))
    }

    public func forecasts(for reading: QuotaReading, accountID: String, provider: String,
                          now: Date = .now) -> [QuotaExhaustionForecast] {
        let current = Self.observations(for: reading, accountID: accountID, provider: provider)
        return entries.compactMap { entry in
            guard !entry.dismissed, let sample = current.first(where: { $0.scope == entry.scope }),
                  let last = entry.observations.last, last.date <= sample.date,
                  last.used <= sample.used, last.limit == sample.limit else { return nil }
            return QuotaExhaustionForecast.estimate(scope: entry.scope, observations: entry.observations, now: now)
        }.sorted { $0.earliest < $1.earliest }
    }

    public mutating func dismiss(_ scope: QuotaForecastScope) {
        for index in entries.indices where Self.sameWindow(entries[index].scope, scope) {
            entries[index].dismissed = true
        }
    }

    private static func sameWindow(_ lhs: QuotaForecastScope, _ rhs: QuotaForecastScope) -> Bool {
        lhs.accountID == rhs.accountID && lhs.provider == rhs.provider && lhs.identity == rhs.identity
            && lhs.window == rhs.window && lhs.resetAt == rhs.resetAt
    }
}
