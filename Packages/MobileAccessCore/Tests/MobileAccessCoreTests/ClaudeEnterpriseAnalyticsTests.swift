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
