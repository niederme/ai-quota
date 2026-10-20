import Foundation
import Testing
@testable import AIQuotaKit

@Test func enterpriseSpendDecoderPreservesScopePeriodAndProviderValues() throws {
    let period = ClaudeEnterprisePeriod(
        startDate: Date(timeIntervalSince1970: 1_780_272_000),
        endDate: Date(timeIntervalSince1970: 1_781_913_600)
    )
    let fetchedAt = Date(timeIntervalSince1970: 1_781_913_700)
    let data = Data(#"{"currency":"USD","series":[{"bucket":"2026-06-01","group_key":"claude_code","group":"Claude Code","cost_minor_units":425,"tokens":{"input":100,"output":20},"request_count":3}],"totals":[{"group_key":"claude_code","group":"Claude Code","cost_minor_units":425,"pct_of_total":100}]}"#.utf8)

    let snapshot = try ClaudeClient._decodeEnterpriseSpendForTesting(
        data,
        scopeID: "123e4567-e89b-12d3-a456-426614174000",
        period: period,
        fetchedAt: fetchedAt
    )

    #expect(snapshot.scopeID == "123e4567-e89b-12d3-a456-426614174000")
    #expect(snapshot.period == period)
    #expect(snapshot.fetchedAt == fetchedAt)
    #expect(snapshot.report.currency == "USD")
    #expect(snapshot.report.series.first?.costMinorUnits == 425)
    #expect(snapshot.report.totals.first?.percentOfTotal == 100)
}

@Test func enterpriseSkillsDecoderKeepsNullCostOptional() throws {
    let period = ClaudeEnterprisePeriod(
        startDate: Date(timeIntervalSince1970: 1_780_272_000),
        endDate: Date(timeIntervalSince1970: 1_781_913_600)
    )
    let data = Data(#"{"items":[{"skill_name":"summarize","invocation_count":2,"total_cost_minor_units":null,"attributed_list_price_minor_units":18}]}"#.utf8)

    let snapshot = try ClaudeClient._decodeEnterpriseSkillsForTesting(
        data,
        scopeID: "123e4567-e89b-12d3-a456-426614174000",
        period: period,
        fetchedAt: .distantPast
    )

    #expect(snapshot.report.items.count == 1)
    #expect(snapshot.report.items[0].skillName == "summarize")
    #expect(snapshot.report.items[0].totalCostMinorUnits == nil)
    #expect(snapshot.report.items[0].attributedListPriceMinorUnits == 18)
}

@Test func enterpriseCurrentMonthUsesUTCReportingBoundary() {
    let instant = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00:00 UTC
    let period = ClaudeEnterprisePeriod.currentMonth(at: instant)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    #expect(calendar.component(.year, from: period.startDate) == 2026)
    #expect(calendar.component(.month, from: period.startDate) == 1)
    #expect(calendar.component(.day, from: period.startDate) == 1)
    #expect(period.endDate == instant)
}

@Test func enterpriseOrganizationScopeRequiresUUID() throws {
    let validated = try ClaudeClient._validatedEnterpriseOrganizationIDForTesting(
        "123E4567-E89B-12D3-A456-426614174000"
    )
    #expect(validated == "123e4567-e89b-12d3-a456-426614174000")
    #expect(throws: (any Error).self) {
        try ClaudeClient._validatedEnterpriseOrganizationIDForTesting("../../usage")
    }
}
