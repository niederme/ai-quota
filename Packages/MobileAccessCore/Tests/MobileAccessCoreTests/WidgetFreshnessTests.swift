import Foundation
import Testing
@testable import MobileAccessCore

@Test func widgetFreshnessExpiresWithoutNewFetch() throws {
    let now = Date(timeIntervalSince1970: 10000)
    let reading = try QuotaReading.decode(Data(#"{"rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":18000},"secondary_window":{"used_percent":100,"limit_window_seconds":604800}}}"#.utf8), now: now)
    #expect(!WidgetFreshness.isOld(reading, at: now.addingTimeInterval(1799)))
    #expect(WidgetFreshness.isOld(reading, at: now.addingTimeInterval(1800)))
    #expect(WidgetFreshness.limitReached(reading))
    #expect(WidgetFreshness.boundaries(reading, after: now) == [now.addingTimeInterval(1800)])
    #expect(reading.fetchedAt == now)
}
@Test func resetBoundaryDoesNotInventReplenishment() throws {
    let now = Date(timeIntervalSince1970: 10000)
    let reading = try QuotaReading.decode(Data(#"{"rate_limit":{"primary_window":{"used_percent":100,"limit_window_seconds":18000,"reset_at":10100},"secondary_window":{"used_percent":30,"limit_window_seconds":604800,"reset_at":10200}}}"#.utf8), now: now)
    #expect(!WidgetFreshness.isOld(reading, at: now))
    #expect(WidgetFreshness.isOld(reading, at: Date(timeIntervalSince1970: 10100)))
    #expect(WidgetFreshness.limitReached(reading))
    #expect(WidgetFreshness.boundaries(reading, after: now).count == 3)
    #expect(WidgetFreshness.isOld(nil, at: now))
    #expect(WidgetFreshness.isOld(reading, at: now.addingTimeInterval(-1)))
}

@Test func monthlyBudgetResetAndLimitAffectWidgetState() throws {
    let now = Date(timeIntervalSince1970: 10000)
    let reset = now.addingTimeInterval(1200)
    let budget = try #require(MonthlyBudget(used: 100, limit: 100, unit: "USD", resetsAt: reset))
    let reading = QuotaReading(fetchedAt: now, shortTerm: nil, weekly: nil, monthlyBudget: budget)
    #expect(reading.primaryDisplayWindow?.usedPercent == 100)
    #expect(WidgetFreshness.limitReached(reading))
    #expect(WidgetFreshness.boundaries(reading, after: now) == [reset, now.addingTimeInterval(1800)])
    #expect(!WidgetFreshness.isOld(reading, at: reset.addingTimeInterval(-1)))
    #expect(WidgetFreshness.isOld(reading, at: reset))
}
