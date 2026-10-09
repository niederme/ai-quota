import Foundation
import Testing
@testable import AIQuotaKit

struct CodexTokenHistoryTests {
    private func response(_ buckets: String) -> Data {
        Data("{\"page\":{\"activity_graph\":{\"daily_usage_buckets\":\(buckets)}}}".utf8)
    }

    @Test func missingAndZeroStayDistinct() throws {
        let history = try #require(try CodexTokenHistory.decode(response("[{\"start_date\":\"2026-10-08\",\"tokens\":0}]")))
        #expect(history.tokensByDate["2026-10-08"] == 0)
        #expect(history.tokensByDate["2026-10-07"] == nil)
        let now = try #require(CodexTokenHistory.dateFormatter().date(from: "2026-10-09"))
        let days = history.days(now: now)
        #expect(days.count == 364)
        #expect(days.first?.key == "2025-10-12")
        #expect(days.last?.key == "2026-10-10")
        #expect(days.filter(\.isFuture).count == 1)
        #expect(days.filter(\.isToday).count == 1)
        #expect(days.first?.tokens == nil)
    }

    @Test func absentGraphAndEmptyHistory() throws {
        #expect(try CodexTokenHistory.decode(Data("{\"page\":{\"activity_graph\":null}}".utf8)) == nil)
        #expect(try CodexTokenHistory.decode(response("[]"))?.tokensByDate.isEmpty == true)
    }

    @Test func rejectsInvalidBuckets() {
        for buckets in ["[{\"start_date\":\"2026-02-30\",\"tokens\":1}]", "[{\"start_date\":\"2026-10-08\",\"tokens\":-1}]", "[{\"start_date\":\"2026-10-08\",\"tokens\":1},{\"start_date\":\"2026-10-08\",\"tokens\":2}]"] {
            #expect(throws: (any Error).self) { try CodexTokenHistory.decode(response(buckets)) }
        }
    }

    @Test func sundayYearBoundaryAndLeapDay() throws {
        let history = try #require(try CodexTokenHistory.decode(response("[]")))
        let formatter = CodexTokenHistory.dateFormatter()
        let sunday = history.days(now: try #require(formatter.date(from: "2027-01-03")))
        #expect(sunday[357].key == "2027-01-03")
        #expect(sunday.filter(\.isFuture).count == 6)
        let leap = history.days(now: try #require(formatter.date(from: "2024-03-01")))
        #expect(leap.contains { $0.key == "2024-02-29" })
        #expect(Set(leap.map(\.key)).count == 364)
    }
}

struct CodexTokenHistoryScopeTests {
    @Test func changesDiscardPriorAccountAndUnknownScope() {
        var scope = CodexTokenHistoryScope()
        let changed = [
            scope.update(scopeID: "account-a"),
            scope.update(scopeID: "account-a"),
            scope.update(scopeID: "account-b"),
            scope.update(scopeID: "account-b"),
            scope.update(scopeID: nil),
            scope.update(scopeID: nil),
            scope.update(scopeID: "account-a"),
        ]
        #expect(changed == [true, false, true, false, true, true, true])
    }

    @Test func sharedWorkspaceCredentialsDoNotShareHistoryScope() {
        let first = CodexAccessContext(accessToken: "fixture-a", accountID: "shared-workspace", source: .codexOAuth)
        let other = CodexAccessContext(accessToken: "fixture-b", accountID: "shared-workspace", source: .codexOAuth)
        let otherWorkspace = CodexAccessContext(accessToken: "fixture-a", accountID: "other-workspace", source: .codexOAuth)
        #expect(OpenAIClient.tokenHistoryScope(for: first) == OpenAIClient.tokenHistoryScope(for: first))
        #expect(OpenAIClient.tokenHistoryScope(for: first) != OpenAIClient.tokenHistoryScope(for: other))
        #expect(OpenAIClient.tokenHistoryScope(for: first) != OpenAIClient.tokenHistoryScope(for: otherWorkspace))
    }

    @Test func responseRetainsRequestAccountIdentity() throws {
        let data = Data("{\"page\":{\"activity_graph\":{\"daily_usage_buckets\":[]}}}".utf8)
        let history = try #require(try CodexTokenHistory.decode(data, scopeID: "account-a"))
        #expect(history.scopeID == "account-a")
    }
}
