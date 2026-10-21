import Foundation
import Testing
@testable import MobileAccessCore

@Test func claudeEnterpriseSpendReportDecodesMinorUnitsAndTokenBuckets() throws {
    let data = Data(#"{"start_date":"2026-10-01","end_date":"2026-10-20","clamped":false,"currency":"USD","group_by":"model","granularity":"day","series":[{"bucket":"2026-10-01","group_key":"sonnet","group":"Claude Sonnet","cost_minor_units":1234,"tokens":{"input":100,"output":20,"cache_read":3,"cache_write_5m":4,"cache_write_1h":5},"request_count":7}],"totals":[{"group_key":"sonnet","group":"Claude Sonnet","cost_minor_units":1234,"pct_of_total":100}]}"#.utf8)
    let report = try JSONDecoder().decode(ClaudeEnterpriseSpendResponse.self, from: data)
    #expect(report.currency == "USD")
    #expect(report.series[0].costMinorUnits == 1234)
    #expect(report.series[0].tokens?.cacheWrite1h == 5)
    #expect(report.totals[0].percentOfTotal == 100)
}

@Test func claudeEnterpriseModelsGracefullyDecodePartialAndNullFields() throws {
    let skills = Data(#"{"start_date":"2026-10-01","items":[{"skill_name":"summarize","invocation_count":2,"total_cost_minor_units":null,"attributed_list_price_minor_units":18,"costs":null}],"has_more":false}"#.utf8)
    let response = try JSONDecoder().decode(ClaudeEnterpriseSkillsResponse.self, from: skills)
    #expect(response.items.count == 1)
    #expect(response.items[0].skillName == "summarize")
    #expect(response.items[0].totalCostMinorUnits == nil)
    #expect(response.items[0].costs == nil)
    let partial = try JSONDecoder().decode(ClaudeEnterpriseSpendResponse.self, from: Data("{}".utf8))
    #expect(partial.series.isEmpty)
    #expect(partial.totals.isEmpty)
}

@Test func claudeOrganizationIDDecodesOnlyAValidOrganizationUUID() {
    #expect(ClaudeAPI.decodeOrganizationID(Data(#"{"organization":{"uuid":"123e4567-e89b-12d3-a456-426614174000"}}"#.utf8)) == "123e4567-e89b-12d3-a456-426614174000")
    #expect(ClaudeAPI.decodeOrganizationID(Data(#"{"organization":{"uuid":"private"}}"#.utf8)) == nil)
    #expect(ClaudeAPI.decodeOrganizationID(Data(#"{"organization":null}"#.utf8)) == nil)
}

@Test func claudeDailyBucketsKeepTheirProviderDateAcrossTimeZones() throws {
    let bucket = try #require(ClaudeEnterpriseDateOnly.bucketDate("2026-10-19"))
    for zone in ["America/New_York", "America/Los_Angeles", "UTC"] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        let parts = calendar.dateComponents([.year, .month, .day], from: bucket)
        #expect(parts.year == 2026)
        #expect(parts.month == 10)
        #expect(parts.day == 19)
    }
    #expect(ClaudeEnterpriseDateOnly.bucketDate("2026-10-19T00:00:00Z") == bucket)
    #expect(ClaudeEnterpriseDateOnly.bucketDate("2026-02-30") == nil)
    #expect(ClaudeEnterpriseDateOnly.displayRange(startDate: "2026-10-01", endDate: "2026-10-20") == "Oct 1–20, 2026 · UTC")
    #expect(ClaudeEnterpriseDateOnly.dayBefore("2026-10-20") == "2026-10-19")
    #expect(ClaudeEnterpriseDateOnly.displayDate("2026-10-19") == "Oct 19, 2026")
}
