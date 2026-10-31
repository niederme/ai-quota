import Foundation

/// The only forecast persistence: user dismissal choices, with no usage values.
public struct QuotaForecastDismissals: Codable, Sendable {
    private var scopes: [QuotaForecastScope] = []
    public init() {}
    public func contains(_ scope: QuotaForecastScope) -> Bool {
        scopes.contains { $0.accountID == scope.accountID && $0.provider == scope.provider
            && $0.identity == scope.identity && $0.window == scope.window && $0.resetAt == scope.resetAt }
    }
    public mutating func dismiss(_ scope: QuotaForecastScope, now: Date = .now) {
        scopes.removeAll { $0.resetAt <= now }
        if !contains(scope) { scopes.append(scope) }
        scopes = Array(scopes.suffix(128))
    }
    public mutating func remove(accountID: String) { scopes.removeAll { $0.accountID == accountID } }
    public mutating func migrateLegacy(_ data: Data, now: Date = .now) {
        struct LegacyEntry: Decodable { let scope: QuotaForecastScope; let dismissed: Bool }
        struct LegacyHistory: Decodable { let entries: [LegacyEntry] }
        let decoder = JSONDecoder()
        let entries = (try? decoder.decode([LegacyEntry].self, from: data))
            ?? (try? decoder.decode(LegacyHistory.self, from: data).entries) ?? []
        for entry in entries where entry.dismissed && entry.scope.resetAt > now { dismiss(entry.scope, now: now) }
    }
}
