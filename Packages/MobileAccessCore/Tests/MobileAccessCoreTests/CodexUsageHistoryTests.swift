import Foundation
import Testing
@testable import MobileAccessCore

private let historyDate = Date(timeIntervalSince1970: 1_790_035_200) // 2026-09-22 UTC

@Test func dailyHistorySumsOnlySurfacesAndKeepsMissingDistinctFromZero() throws {
    let today = CodexUsageHistory.dateString(historyDate)
    let yesterday = CodexUsageHistory.dateString(historyDate.addingTimeInterval(-86400))
    let history = try CodexUsageHistory.decode(Data("""
    {"data":[
      {"date":"\(today)","product_surface_usage_values":{"cli":2,"desktop_app":3},"models":[{"credits":5}]},
      {"date":"\(yesterday)","product_surface_usage_values":{"cli":0}}
    ]}
    """.utf8), now: historyDate)
    #expect(history.days.count == 30)
    #expect(history.days.last?.credits == 5)
    #expect(history.days[28].credits == 0)
    #expect(history.days[27].credits == nil)
    #expect(history.days.map(\.date) == history.days.map(\.date).sorted())
    #expect(try JSONDecoder().decode(CodexUsageHistory.self, from: JSONEncoder().encode(history)) == history)
}

@Test func invalidDailyHistoryDoesNotBecomeAZeroChart() {
    for data in [
        #"{"data":[{"date":"2026-09-22","product_surface_usage_values":{"cli":-1}}]}"#,
        #"{"data":[{"date":"2026-09-22","product_surface_usage_values":{}}]}"#,
        #"{"data":[{"date":"2026-09-22","product_surface_usage_values":{"cli":1}},{"date":"2026-09-22","product_surface_usage_values":{"cli":2}}]}"#,
        #"{"unexpected":[]}"#
    ] {
        #expect(throws: (any Error).self) { try CodexUsageHistory.decode(Data(data.utf8), now: historyDate) }
    }
}

private struct HistoryTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResult {
        #expect(request.url?.path == "/backend-api/wham/usage/daily-token-usage-breakdown")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(query.contains(URLQueryItem(name: "group_by", value: "day")))
        #expect(query.contains(URLQueryItem(name: "end_date", value: CodexUsageHistory.dateString(historyDate))))
        #expect(query.contains(URLQueryItem(name: "start_date", value: CodexUsageHistory.dateString(historyDate.addingTimeInterval(-29 * 86400)))))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "test-account")
        return HTTPResult(data: Data(#"{"data":[]}"#.utf8), status: 200)
    }
}
@Test func historyRequestUsesExistingAccountAndDailyRange() async throws {
    let tokens = try JSONDecoder().decode(CodexTokens.self, from: Data(#"{"accessToken":"synthetic","accountID":"test-account","expiresAt":900000000}"#.utf8))
    let history = try await CodexAPI(transport: HistoryTransport()).usageHistory(tokens, now: historyDate)
    #expect(history.days.count == 30)
    #expect(history.days.allSatisfy { $0.credits == nil })
}

@Test func modelAndSurfaceAttributionRemainSeparateAndCombineSpeeds() throws {
    let date = CodexUsageHistory.dateString(historyDate)
    let history = try CodexUsageHistory.decode(Data("""
    {"data":[{"date":"\(date)","product_surface_usage_values":{"cli":3,"desktop_app":2},
    "models":[{"model":"astra","speed":"standard","credits":2},
              {"model":"astra","speed":"fast","credits":1},
              {"model":"sol","credits":2}]}]}
    """.utf8), now: historyDate)
    #expect(history.days.last?.credits == 5)
    #expect(history.days.last?.models == ["astra":3,"sol":2])
    #expect(history.days.last?.surfaces == ["cli":3,"desktop_app":2])
    #expect(try JSONDecoder().decode(CodexUsageHistory.self, from: JSONEncoder().encode(history)) == history)
}

@Test func olderCachedHistoryWithoutBreakdownsStillDecodes() throws {
    let data = Data(#"{"fetchedAt":0,"days":[{"date":"2026-09-21","credits":5}]}"#.utf8)
    let history = try JSONDecoder().decode(CodexUsageHistory.self, from: data)
    #expect(history.days.first?.credits == 5)
    #expect(history.days.first?.models == nil)
    #expect(history.days.first?.surfaces == nil)
}

@Test func emptyOrZeroHistoryHidesChart() throws {
    for json in [#"{"data":[]}"#, "{\"data\":[{\"date\":\"\(CodexUsageHistory.dateString(historyDate))\",\"product_surface_usage_values\":{\"cli\":0}}]}"] {
        let history = try CodexUsageHistory.decode(Data(json.utf8), now: historyDate)
        #expect(!history.hasChartData)
        #expect(history.chartDays.isEmpty)
        #expect(history.chartRangeLabel.isEmpty)
    }
}

@Test func newHistoryStartsAtLeftAndRetainsCalendarGaps() throws {
    let firstDate = CodexUsageHistory.dateString(historyDate.addingTimeInterval(-3 * 86400))
    let yesterday = CodexUsageHistory.dateString(historyDate.addingTimeInterval(-86400))
    let today = CodexUsageHistory.dateString(historyDate)
    let history = try CodexUsageHistory.decode(Data("""
    {"data":[{"date":"\(firstDate)","product_surface_usage_values":{"cli":2}},
             {"date":"\(yesterday)","product_surface_usage_values":{"cli":0}},
             {"date":"\(today)","product_surface_usage_values":{"cli":4}}]}
    """.utf8), now: historyDate)
    #expect(history.hasChartData)
    #expect(history.chartDays.count == 4)
    #expect(history.chartDays.first?.date == firstDate)
    #expect(history.chartDays.map(\.credits) == [2, nil, 0, 4])
    #expect(history.days.count == 30)
}

@Test func firstUsageDayOccupiesOnlyFirstSlot() throws {
    let today = CodexUsageHistory.dateString(historyDate)
    let history = try CodexUsageHistory.decode(Data("{\"data\":[{\"date\":\"\(today)\",\"product_surface_usage_values\":{\"cli\":4}}]}".utf8), now: historyDate)
    #expect(history.chartDays.count == 1)
    #expect(history.chartDays[0].credits == 4)
}
