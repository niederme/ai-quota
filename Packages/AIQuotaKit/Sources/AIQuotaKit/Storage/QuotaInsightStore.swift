import Foundation
import MobileAccessCore

/// Stores only dismissal preferences. Forecast inputs and service history stay ephemeral.
public actor QuotaInsightStore {
    public static let shared = QuotaInsightStore(suiteName:
        Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
            ? "QuotaInsightTests.clients.\(ProcessInfo.processInfo.processIdentifier)" : nil)
    private static let legacyKey = "quotaPaceObservations.v1"
    private static let key = "quotaForecastDismissals.v2"
    private let defaults: UserDefaults
    private let accountLookup: @Sendable (String) -> ConnectedAccount?
    private var dismissals: QuotaForecastDismissals

    public init(suiteName: String? = nil,
                accountLookup: @escaping @Sendable (String) -> ConnectedAccount? = { AccountRegistry.account(id: $0) }) {
        self.accountLookup = accountLookup
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.defaults = defaults
        var dismissals = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(QuotaForecastDismissals.self, from: $0) } ?? .init()
        if let legacy = defaults.data(forKey: Self.legacyKey) {
            dismissals.migrateLegacy(legacy)
            defaults.set(try? JSONEncoder().encode(dismissals), forKey: Self.key)
        }
        defaults.removeObject(forKey: Self.legacyKey)
        self.dismissals = dismissals
    }

    /// Referenced at startup so migration also runs when no alert is eligible.
    public func prepare() {}
    public func clear() {
        dismissals = .init()
        defaults.removeObject(forKey: Self.key)
        defaults.removeObject(forKey: Self.legacyKey)
    }
    public func remove(accountID: String) { dismissals.remove(accountID: accountID); save() }
    public func visible(_ forecasts: [QuotaExhaustionForecast]) -> [QuotaExhaustionForecast] {
        forecasts.filter {
            guard let account = accountLookup($0.scope.accountID), account.workspaceID == $0.scope.identity,
                  account.provider.rawValue == $0.scope.provider else { return false }
            return !dismissals.contains($0.scope)
        }
    }
    public func dismiss(_ scope: QuotaForecastScope) {
        guard accountLookup(scope.accountID)?.workspaceID == scope.identity else { return }
        dismissals.dismiss(scope); save()
    }
    private func save() { defaults.set(try? JSONEncoder().encode(dismissals), forKey: Self.key) }
}
