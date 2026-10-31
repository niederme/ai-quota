import Testing
import Foundation
@testable import MobileAccessCore

private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
private let now = date("2026-10-29T12:00:00Z")
private let reset = date("2026-11-02T00:00:00Z")
private func input(used: Double = 65, at: Date = now, resetAt: Date = reset,
                   duration: Double = 604800, window: QuotaForecastScope.Window = .weekly) -> QuotaForecastInput {
    .init(scope: .init(accountID: "a", provider: "codex", identity: "workspace", source: "wham", plan: "pro",
                      window: window, resetAt: resetAt), usedPercent: used, duration: duration, fetchedAt: at)
}
private func history(_ values: [Double], at: Date = now) -> QuotaForecastDailyHistory {
    let calendar = CodexTokenHistory.calendar
    let end = calendar.startOfDay(for: at)
    let dates = (1...28).map { end.addingTimeInterval(-Double($0) * 86400) }
    return .init(values: Dictionary(uniqueKeysWithValues: dates.map {
        (CodexTokenHistory.dateStringForTest($0), values[calendar.component(.weekday, from: $0) - 1])
    }), fetchedAt: at)
}
private extension CodexTokenHistory {
    static func dateStringForTest(_ date: Date) -> String { dateFormatter().string(from: date) }
}

@Test func forecastsImmediatelyWithoutAnyLocallyRecordedSamples() throws {
    let result = try #require(QuotaExhaustionForecast.estimate(input(), now: now))
    #expect(result.basis == .periodAverage)
    #expect(abs(result.projectedUsedPercent - 130) < 0.001)
    #expect(result.validUntil == now.addingTimeInterval(3600))
}
@Test func timeOfDayChangesProjectionWithoutTreatingPartialDayAsComplete() {
    let morning = date("2026-10-29T06:00:00Z"), evening = date("2026-10-29T22:00:00Z")
    #expect(QuotaExhaustionForecast.estimate(input(used: 60, at: morning), now: morning) != nil)
    #expect(QuotaExhaustionForecast.estimate(input(used: 60, at: evening), now: evening) == nil)
    // Do not reinterpret an old snapshot as fresh quiet time merely because the clock advanced.
    #expect(QuotaExhaustionForecast.estimate(input(used: 60, at: morning), now: evening) == nil)
}
@Test func upcomingBusyFridayDiffersFromBusyMidweek() throws {
    let monFri = history([1, 100, 10, 10, 10, 100, 1])
    let midweek = history([1, 10, 100, 100, 100, 10, 1])
    let result = try #require(QuotaExhaustionForecast.estimate(input(), history: monFri, now: now))
    #expect(result.basis == .weeklyPattern)
    #expect(QuotaExhaustionForecast.estimate(input(), history: midweek, now: now) == nil)
}
@Test func dailyPatternsDoNotInventMorningOrNightWorkingHours() throws {
    let morning = date("2026-10-29T06:00:00Z"), night = date("2026-10-29T23:00:00Z")
    let pattern = [1.0, 100, 10, 10, 10, 100, 1]
    let early = try #require(QuotaExhaustionForecast.estimate(input(at: morning), history: history(pattern, at: morning), now: morning))
    let late = try #require(QuotaExhaustionForecast.estimate(input(at: night), history: history(pattern, at: night), now: night))
    #expect(early.basis == .weeklyPattern)
    #expect(early.projectedUsedPercent == late.projectedUsedPercent)
    // Even a historically busy day may already be finished for a night worker.
    // Do not predict more use in that partial day when no full days remain.
    let sunday = date("2026-11-01T01:00:00Z")
    #expect(QuotaExhaustionForecast.estimate(input(used: 95, at: sunday),
        history: history([100,10,10,10,10,10,100], at: sunday), now: sunday) == nil)
}
@Test func weekendHeavyPatternIsNotAssumedToBeAWorkweek() throws {
    let weekend = history([100, 10, 10, 10, 10, 10, 100])
    let weekdays = history([1, 100, 100, 100, 100, 100, 1])
    let result = try #require(QuotaExhaustionForecast.estimate(input(used: 50), history: weekend, now: now))
    #expect(result.basis == .weeklyPattern)
    #expect(QuotaExhaustionForecast.estimate(input(used: 50), history: weekdays, now: now) == nil)
}
@Test func stableDailyUseRetainsSimpleAverage() throws {
    let result = try #require(QuotaExhaustionForecast.estimate(input(), history: history(Array(repeating: 30, count: 7)), now: now))
    #expect(result.basis == .periodAverage)
}
@Test func missingDaysAreNotZerosAndStaleHistoryFallsBack() throws {
    let full = history([1, 100, 10, 10, 10, 100, 1])
    var values = full.values
    values.removeValue(forKey: "2026-10-10")
    for h in [QuotaForecastDailyHistory(values: values, fetchedAt: now),
              .init(values: full.values, fetchedAt: now.addingTimeInterval(-37 * 3600))] {
        #expect(try #require(QuotaExhaustionForecast.estimate(input(), history: h, now: now)).basis == .periodAverage)
    }
}
@Test func incompleteTodayAndFutureDoNotTrainPattern() {
    let original = history([1, 100, 10, 10, 10, 100, 1])
    var values = original.values
    values["2026-10-29"] = 1e20; values["2026-10-30"] = 1e20
    #expect(QuotaExhaustionForecast.weekdayWeights(original, now: now) ==
            QuotaExhaustionForecast.weekdayWeights(.init(values: values, fetchedAt: now), now: now))
}
@Test func suddenScheduleChangeFailsHeldOutWeek() {
    let original = history([1, 100, 10, 10, 10, 100, 1])
    var values = original.values
    for offset in 1...7 {
        values[CodexTokenHistory.dateStringForTest(now.addingTimeInterval(-Double(offset) * 86400))] = 40
    }
    #expect(QuotaExhaustionForecast.weekdayWeights(.init(values: values, fetchedAt: now), now: now) == nil)
}
@Test func burstDoesNotInventARecurringSchedule() {
    var values = history(Array(repeating: 20, count: 7)).values
    values["2026-10-10"] = 10000
    #expect(QuotaExhaustionForecast.weekdayWeights(.init(values: values, fetchedAt: now), now: now) == nil)
}
@Test func absoluteTokenOrCreditScaleDoesNotConvertIntoQuotaPercent() {
    let a = history([1, 100, 10, 10, 10, 100, 1])
    let b = QuotaForecastDailyHistory(values: a.values.mapValues { $0 * 10000 }, fetchedAt: now)
    let x = QuotaExhaustionForecast.estimate(input(), history: a, now: now)
    let y = QuotaExhaustionForecast.estimate(input(), history: b, now: now)
    #expect(x?.basis == y?.basis)
    #expect(abs((x?.projectedUsedPercent ?? 0) - (y?.projectedUsedPercent ?? 0)) < 0.0001)
}
@Test func invalidSnapshotsAndEarlyPeriodDoNotProduceWarnings() {
    for percent in [0.0, 100, -1, .nan, .infinity] {
        #expect(QuotaExhaustionForecast.estimate(input(used: percent), now: now) == nil)
    }
    #expect(QuotaExhaustionForecast.estimate(input(resetAt: now), now: now) == nil)
    #expect(QuotaExhaustionForecast.estimate(input(at: now.addingTimeInterval(1)), now: now) == nil)
    #expect(QuotaExhaustionForecast.estimate(input(at: now.addingTimeInterval(-3601)), now: now) == nil)
    #expect(QuotaExhaustionForecast.estimate(input(resetAt: now.addingTimeInterval(6.9 * 86400)), now: now) == nil)
    #expect(QuotaExhaustionForecast.estimate(input(duration: .nan), now: now) == nil)
}
@Test func fiveHourWindowUsesClockTimeAndNeverDailyPattern() throws {
    let result = try #require(QuotaExhaustionForecast.estimate(input(used: 70, resetAt: now.addingTimeInterval(3 * 3600), duration: 18000, window: .fiveHour),
        history: history([1,100,10,10,10,100,1]), now: now))
    #expect(result.basis == .periodAverage)
}
@Test func budgetsWithoutKnownDurationAndUnknownIdentityAreOmitted() {
    let metadata = AccountMetadata(plan: "pro", balanceUSD: nil, usageSpent: nil, usageCurrency: nil)
    let reading = QuotaReading(fetchedAt: now, shortTerm: nil, weekly: nil, metadata: metadata,
        monthlyBudget: .init(used: 80, limit: 100, unit: "credits", resetsAt: reset), providerIdentity: "workspace")
    #expect(QuotaForecastInput.inputs(for: reading, accountID: "a", provider: "codex").isEmpty)
    let unknown = QuotaReading(fetchedAt: now, shortTerm: nil,
        weekly: .init(usedPercent: 80, durationSeconds: 604800, resetsAt: reset), metadata: metadata)
    #expect(QuotaForecastInput.inputs(for: unknown, accountID: "a", provider: "codex").isEmpty)
}
@Test func legacyMigrationPersistsOnlyDismissals() throws {
    let scope = input().scope
    let encoded = String(data: try JSONEncoder().encode(scope), encoding: .utf8)!
    for legacy in ["[{\"scope\":\(encoded),\"dismissed\":true,\"observations\":[{\"used\":65}]}]",
                   "{\"entries\":[{\"scope\":\(encoded),\"dismissed\":true,\"observations\":[{\"used\":65}]}]}"] {
        var value = QuotaForecastDismissals()
        value.migrateLegacy(Data(legacy.utf8), now: now)
        let data = try JSONEncoder().encode(value)
        let text = String(data: data, encoding: .utf8)!
        #expect(!text.contains("observations") && !text.contains("used"))
        #expect(try JSONDecoder().decode(QuotaForecastDismissals.self, from: data).contains(scope))
        #expect(!value.contains(input(resetAt: reset.addingTimeInterval(7*86400)).scope))
        value.remove(accountID: "a")
        #expect(!value.contains(scope))
    }
}
