import Foundation
import Testing
@testable import MobileAccessCore

@Test func analyticsKeepsUnknownDaysAndUnknownAttributionDistinctFromZero() throws {
    let now = Date(timeIntervalSince1970: 1_790_035_200)
    let dates = (0..<4).reversed().map { CodexUsageHistory.dateString(now.addingTimeInterval(-Double($0) * 86400)) }
    let history = try CodexUsageHistory.decode(Data("""
    {"data":[
      {"date":"\(dates[0])","product_surface_usage_values":{"cli":6},"models":[{"model":"a","credits":6}]},
      {"date":"\(dates[2])","product_surface_usage_values":{"desktop_app":0},"models":[{"model":"b","credits":0}]},
      {"date":"\(dates[3])","product_surface_usage_values":{"desktop_app":4}}
    ]}
    """.utf8), now: now)
    let period = CodexHistoryPeriod(history: history, count: 4)
    #expect(period.total == 10)
    #expect(period.reportedDays == 3)
    #expect(period.isPartial)
    #expect(period.series(.models).first?.values == [6, nil, 0, nil])
    #expect(period.series(.surfaces).first?.id == "cli")
    #expect(period.series(.surfaces).first?.values == [6, nil, 0, 0])
    #expect(period.missingAttribution(.models))
    #expect(!period.missingAttribution(.surfaces))
}

@Test func analyticsPeriodSelectionUsesCalendarSlotsAndSeparateAttributionTotals() throws {
    let now = Date(timeIntervalSince1970: 1_790_035_200)
    let today = CodexUsageHistory.dateString(now)
    let older = CodexUsageHistory.dateString(now.addingTimeInterval(-8 * 86400))
    let history = try CodexUsageHistory.decode(Data("""
    {"data":[
      {"date":"\(today)","product_surface_usage_values":{"cli":3,"desktop_app":2},
       "models":[{"model":"b","credits":2},{"model":"a","credits":3}]},
      {"date":"\(older)","product_surface_usage_values":{"cli":8}}
    ]}
    """.utf8), now: now)
    #expect(CodexHistoryPeriod(history: history, count: 7).total == 5)
    #expect(CodexHistoryPeriod(history: history, count: 30).total == 13)
    #expect(CodexHistoryPeriod(history: history, count: 7).series(.models).map(\.total) == [3, 2])
    #expect(CodexHistoryPeriod(history: history, count: 7).series(.surfaces).map(\.total) == [3, 2])
    #expect(CodexHistoryPeriod(history: nil, count: 7).days.isEmpty)
}

@Test func historyDateLabelsUseProviderCalendarDate() throws {
    let date = try #require(CodexHistoryPeriod.date("2026-09-22"))
    #expect(CodexUsageHistory.dateString(date) == "2026-09-22")
    #expect(CodexHistoryPeriod.date("bad-date") == nil)
}
