import Foundation
import Testing
@testable import MobileAccessCore

@Test func codexCreditsUseMacDollarConversion() throws {
    let data = Data(#"{"plan_type":"plus","credits":{"balance":"359.5"},"rate_limit":{"primary_window":{"used_percent":40,"limit_window_seconds":18000}}}"#.utf8)
    let reading = try QuotaReading.decode(data, now: .now)
    #expect(reading.metadata?.plan == "plus")
    #expect(reading.metadata?.balanceUSD == 14.38)
    #expect(reading.shortTerm?.usedPercent == 40)
}
@Test func missingAndMalformedMetadataDoNotInventZero() throws {
    for credits in ["null", #"{"balance":"unknown"}"#, #"{"balance":-20}"#] {
        let data = Data("{\"credits\":\(credits),\"rate_limit\":{\"primary_window\":{\"used_percent\":0,\"limit_window_seconds\":18000}}}".utf8)
        #expect(try QuotaReading.decode(data, now: .now).metadata?.balanceUSD == nil)
    }
}
@Test func claudeStructuredSpendUsesExponent() throws {
    let data = Data(#"{"five_hour":{"utilization":5},"spend":{"used":{"amount_minor":1558,"currency":"USD","exponent":2}},"extra_usage":{"used_credits":99}}"#.utf8)
    let reading = try ClaudeAPI.decodeUsage(data, now: .now)
    #expect(reading.metadata?.usageSpent == 15.58)
    #expect(reading.metadata?.usageCurrency == "USD")
    #expect(reading.metadata?.plan == nil)
}
@Test func claudeOAuthFallbackKeepsProviderUnits() throws {
    let data = Data(#"{"five_hour":{"utilization":5},"extra_usage":{"used_credits":1558}}"#.utf8)
    let reading = try ClaudeAPI.decodeUsage(data, now: .now)
    #expect(reading.metadata?.usageSpent == 1558)
    #expect(reading.metadata?.usageCurrency == nil)
}
@Test func oldCachedReadingStillDecodesAndNewMetadataRoundTrips() throws {
    let data = Data(#"{"fetchedAt":100,"shortTerm":{"usedPercent":12,"durationSeconds":18000},"weekly":null}"#.utf8)
    let old = try JSONDecoder().decode(QuotaReading.self, from: data)
    #expect(old.metadata == nil)
    #expect(old.shortTerm?.usedPercent == 12)
    let updated = QuotaReading(fetchedAt: old.fetchedAt, shortTerm: old.shortTerm, weekly: nil,
        metadata: AccountMetadata(plan: "plus", balanceUSD: 0, usageSpent: nil, usageCurrency: nil))
    #expect(try JSONDecoder().decode(QuotaReading.self, from: JSONEncoder().encode(updated)) == updated)
}

@Test func codexSpendingFiltersMonthAndConvertsCredits() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
    let data = Data(#"{"data":[{"date":"2026-09-02","credit_amount":250},{"date":"2026-08-31","credit_amount":1000},{"date":"2026-09-12","credit_amount":25}]}"#.utf8)
    #expect(try CodexAPI.decodeSpending(data, now: now, calendar: calendar) == 11)
    #expect(throws: (any Error).self) {
        try CodexAPI.decodeSpending(Data(#"{"data":[{"date":"bad","credit_amount":10}]}"#.utf8), now: now)
    }
}

@Test func upgradedProWeeklyWindowKeepsMissingFiveHourWindowAbsent() throws {
    let reading = try QuotaReading.decode(Data(#"{"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":1,"limit_window_seconds":604800}}}"#.utf8), now: .now)
    #expect(reading.shortTerm == nil)
    #expect(reading.weekly?.usedPercent == 1)
    #expect(reading.metadata?.plan == "prolite")
    #expect(reading.metadata?.displayPlan == "Pro")
}
