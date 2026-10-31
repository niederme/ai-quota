import Testing
import Foundation
@testable import MobileAccessCore

private let forecastNow = Date(timeIntervalSince1970: 1_800_000_000)
private func forecastReading(_ hour: Int, identity: String? = "workspace", plan: String = "pro", used: Double? = nil,
                             reset: Date = forecastNow.addingTimeInterval(4 * 86400)) -> QuotaReading {
    QuotaReading(fetchedAt: forecastNow.addingTimeInterval(Double(hour - 24) * 3600), shortTerm: nil,
        weekly: .init(usedPercent: used ?? (25 + Double(hour) * 40 / 24), durationSeconds: 604800, resetsAt: reset),
        metadata: .init(plan: plan, balanceUSD: nil, usageSpent: nil, usageCurrency: nil), providerIdentity: identity)
}
private func populatedHistory() -> QuotaForecastHistory {
    var history = QuotaForecastHistory()
    for hour in 0...24 {
        let reading = forecastReading(hour)
        history.record(reading, accountID: "personal", provider: "codex", now: reading.fetchedAt)
    }
    return history
}

@Test func mobileForecastRequiresSufficientVerifiedObservations() {
    var history = QuotaForecastHistory()
    history.record(forecastReading(24), accountID: "personal", provider: "codex", now: forecastNow)
    #expect(history.forecasts(for: forecastReading(24), accountID: "personal", provider: "codex", now: forecastNow).isEmpty)
    let full = populatedHistory()
    #expect(full.forecasts(for: forecastReading(24), accountID: "personal", provider: "codex", now: forecastNow).count == 1)
    #expect(full.forecasts(for: forecastReading(24), accountID: "work", provider: "codex", now: forecastNow).isEmpty)
    #expect(full.forecasts(for: forecastReading(24), accountID: "personal", provider: "claude", now: forecastNow).isEmpty)
    #expect(full.forecasts(for: forecastReading(24, identity: "different"), accountID: "personal", provider: "codex", now: forecastNow).isEmpty)
    #expect(full.forecasts(for: forecastReading(24, plan: "business"), accountID: "personal", provider: "codex", now: forecastNow).isEmpty)
    #expect(full.forecasts(for: forecastReading(24), accountID: "personal", provider: "codex", now: forecastNow.addingTimeInterval(3601)).isEmpty)
}

@Test func mobileForecastRejectsMissingIdentityUnknownPlanAndReset() {
    #expect(QuotaForecastHistory.observations(for: forecastReading(24, identity: nil), accountID: "a", provider: "codex").isEmpty)
    #expect(QuotaForecastHistory.observations(for: forecastReading(24, plan: "unknown"), accountID: "a", provider: "codex").isEmpty)
    let reading = QuotaReading(fetchedAt: forecastNow, shortTerm: nil,
        weekly: .init(usedPercent: 80, durationSeconds: 604800, resetsAt: nil),
        metadata: forecastReading(24).metadata, providerIdentity: "workspace")
    #expect(QuotaForecastHistory.observations(for: reading, accountID: "a", provider: "codex").isEmpty)
}

@Test func mobileForecastKeepsActualMonthlyAndUnsupportedWindowSemantics() {
    for (duration, expected) in [(30 * 86400, QuotaForecastScope.Window.monthly), (18000, .fiveHour), (604800, .weekly)] {
        let reading = QuotaReading(fetchedAt: forecastNow, shortTerm: nil,
            weekly: .init(usedPercent: 80, durationSeconds: duration, resetsAt: forecastNow.addingTimeInterval(3600)),
            metadata: forecastReading(24).metadata, providerIdentity: "workspace")
        #expect(QuotaForecastHistory.observations(for: reading, accountID: "a", provider: "claude").first?.scope.window == expected)
    }
    let unsupported = QuotaReading(fetchedAt: forecastNow, shortTerm: .init(usedPercent: 50, durationSeconds: 7200,
        resetsAt: forecastNow.addingTimeInterval(3600)), weekly: nil, metadata: forecastReading(24).metadata, providerIdentity: "workspace")
    #expect(QuotaForecastHistory.observations(for: unsupported, accountID: "a", provider: "codex").isEmpty)
    let noReset = QuotaReading(fetchedAt: forecastNow, shortTerm: nil, weekly: nil, metadata: forecastReading(24).metadata,
        monthlyBudget: .init(used: 85, limit: 100, unit: "USD"), providerIdentity: "workspace")
    #expect(QuotaForecastHistory.observations(for: noReset, accountID: "a", provider: "claude").isEmpty)
}

@Test func mobileForecastDismissalSurvivesPersistenceAndCorrections() throws {
    var history = populatedHistory()
    let forecast = try #require(history.forecasts(for: forecastReading(24), accountID: "personal", provider: "codex", now: forecastNow).first)
    history.dismiss(forecast.scope)
    var restored = try JSONDecoder().decode(QuotaForecastHistory.self, from: JSONEncoder().encode(history))
    #expect(restored.forecasts(for: forecastReading(24), accountID: "personal", provider: "codex", now: forecastNow).isEmpty)
    let correction = forecastReading(25, used: 30)
    restored.record(correction, accountID: "personal", provider: "codex", now: correction.fetchedAt)
    #expect(restored.entries.first?.observations.count == 1)
    #expect(restored.entries.first?.dismissed == true)
    let changedPlan = forecastReading(26, plan: "plus")
    restored.record(changedPlan, accountID: "personal", provider: "codex", now: changedPlan.fetchedAt)
    #expect(restored.entries.last?.dismissed == true)
    let nextWindow = forecastReading(27, reset: forecastNow.addingTimeInterval(7 * 86400))
    restored.record(nextWindow, accountID: "personal", provider: "codex", now: nextWindow.fetchedAt)
    #expect(restored.entries.last?.dismissed == false)
}

@Test func mobileForecastDeduplicatesAndSeparatesReplacementIdentity() {
    var history = populatedHistory()
    history.record(forecastReading(24), accountID: "personal", provider: "codex", now: forecastNow)
    #expect(history.entries.first?.observations.count == 25)
    let later = QuotaReading(fetchedAt: forecastNow.addingTimeInterval(60), shortTerm: nil,
        weekly: forecastReading(24).weekly, metadata: forecastReading(24).metadata, providerIdentity: "workspace")
    history.record(later, accountID: "personal", provider: "codex", now: later.fetchedAt)
    #expect(history.entries.first?.observations.count == 25)
    #expect(history.forecasts(for: later, accountID: "personal", provider: "codex", now: later.fetchedAt).count == 1)
    let replacement = forecastReading(25, identity: "new-workspace")
    history.record(replacement, accountID: "personal", provider: "codex", now: replacement.fetchedAt)
    #expect(history.entries.count == 1)
    #expect(history.entries.first?.scope.identity == "new-workspace")
    #expect(history.forecasts(for: replacement, accountID: "personal", provider: "codex", now: replacement.fetchedAt).isEmpty)
}
