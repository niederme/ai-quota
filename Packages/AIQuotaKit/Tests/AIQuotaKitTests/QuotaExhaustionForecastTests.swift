import Foundation
import Testing
@testable import AIQuotaKit

@Test func quotaInsightMigratesWithoutRetainingUsageAndDismissesAcrossLaunches() async throws {
    let suite = "QuotaInsightTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = ConnectedAccount(provider: .codex, displayLabel: "Personal", workspaceID: "workspace", authSource: .webSession, connectionKind: .legacyPrimary)
    // An absent account must never inherit a persisted dismissal/forecast.
    let store = QuotaInsightStore(suiteName: suite, accountLookup: { _ in nil })
    let scope = QuotaForecastScope(accountID: account.id, provider: "codex", identity: "workspace",
        source: "wham", plan: "pro", window: .weekly, resetAt: .now.addingTimeInterval(86400))
    let value = QuotaExhaustionForecast(scope: scope, basis: .periodAverage, projectedUsedPercent: 140,
                                        validUntil: .now.addingTimeInterval(3600))
    #expect(await store.visible([value]).isEmpty)
    let encoded = String(data: try JSONEncoder().encode(scope), encoding: .utf8)!
    defaults.set(Data("[{\"scope\":\(encoded),\"dismissed\":true,\"observations\":[{\"used\":65}]}]".utf8), forKey: "quotaPaceObservations.v1")
    let migrated = QuotaInsightStore(suiteName: suite, accountLookup: { _ in account })
    await migrated.prepare()
    #expect(defaults.object(forKey: "quotaPaceObservations.v1") == nil)
    let data = try #require(defaults.data(forKey: "quotaForecastDismissals.v2"))
    #expect(!String(decoding: data, as: UTF8.self).contains("observations"))
    #expect(await migrated.visible([value]).isEmpty)
    await migrated.clear()
    #expect(defaults.object(forKey: "quotaForecastDismissals.v2") == nil)
    #expect(await migrated.visible([value]).count == 1)
    await migrated.dismiss(scope)
    let reopened = QuotaInsightStore(suiteName: suite, accountLookup: { _ in account })
    #expect(await reopened.visible([value]).isEmpty)
    await reopened.remove(accountID: account.id)
    #expect(await reopened.visible([value]).count == 1)
}
