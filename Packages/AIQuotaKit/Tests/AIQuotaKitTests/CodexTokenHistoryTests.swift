import Foundation
import Testing
@testable import AIQuotaKit

struct CodexTokenHistoryTests {
    @Test func workspaceProfileUsesOnlyAccountUsageSchema() throws {
        let data = Data(#"{"profile":{"display_name":"Same name across workspaces"},"metadata":{"stats_error":null,"stats_as_of":"2026-10-08"},"stats":{"daily_usage_buckets":[{"start_date":"2026-10-08","tokens":500},{"start_date":"2026-10-09","tokens":0}]}}"#.utf8)
        let personal = try #require(try CodexTokenHistory.decodeWorkspaceProfile(data, workspaceID: "personal", scopeID: "request-a"))
        let work = try #require(try CodexTokenHistory.decodeWorkspaceProfile(data, workspaceID: "work", scopeID: "request-b"))
        #expect(personal.tokensByDate["2026-10-08"] == 500)
        #expect(personal.tokensByDate["2026-10-09"] == 0)
        #expect(personal.tokensByDate["2026-10-10"] == nil)
        #expect(personal.isAttributed(toWorkspaceID: "personal"))
        #expect(!personal.isAttributed(toWorkspaceID: "work"))
        #expect(work.isAttributed(toWorkspaceID: "work"))
        #expect(!work.isAttributed(toWorkspaceID: "personal"))
        // Identical names/counts are not used to infer or merge identities.
        #expect(personal.tokensByDate == work.tokensByDate)
        #expect(personal.scopeID != work.scopeID)
        #expect(try CodexTokenHistory.decodeWorkspaceProfile(response("[{\"start_date\":\"2026-10-08\",\"tokens\":500}]"), workspaceID: "personal", scopeID: "request-a") == nil)
    }

    @Test func unavailableWorkspaceStatsNeverBecomeZeroHistory() throws {
        for payload in [#"{}"#, #"{"stats":{}}"#, #"{"stats":{"daily_usage_buckets":null}}"#,
                        #"{"metadata":{"stats_error":"unavailable"},"stats":{"daily_usage_buckets":[{"start_date":"2026-10-08","tokens":500}]}}"#] {
            #expect(try CodexTokenHistory.decodeWorkspaceProfile(Data(payload.utf8), workspaceID: "work", scopeID: "request-b") == nil)
        }
        let empty = try #require(try CodexTokenHistory.decodeWorkspaceProfile(Data(#"{"stats":{"daily_usage_buckets":[]}}"#.utf8), workspaceID: "work", scopeID: "request-b"))
        #expect(empty.tokensByDate.isEmpty)
        #expect(empty.isAttributed(toWorkspaceID: "work"))
    }

    @Test func workspaceProfileRequiresBoundScopeAndValidIntegerBuckets() {
        let empty = Data(#"{"stats":{"daily_usage_buckets":[]}}"#.utf8)
        for (workspace, scope) in [("", "request"), ("work", "")] {
            #expect(throws: (any Error).self) {
                try CodexTokenHistory.decodeWorkspaceProfile(empty, workspaceID: workspace, scopeID: scope)
            }
        }
        for buckets in [#"[{"start_date":"2026-02-30","tokens":1}]"#,
                        #"[{"start_date":"2026-10-08","tokens":-1}]"#,
                        #"[{"start_date":"2026-10-08","tokens":1.5}]"#,
                        #"[{"start_date":"2026-10-08","tokens":1},{"start_date":"2026-10-08","tokens":2}]"#] {
            let data = Data("{\"stats\":{\"daily_usage_buckets\":\(buckets)}}".utf8)
            #expect(throws: (any Error).self) {
                try CodexTokenHistory.decodeWorkspaceProfile(data, workspaceID: "work", scopeID: "request-b")
            }
        }
    }

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

    @Test func profileHistoryNeverClaimsWorkspaceAttribution() throws {
        for tokens in [0, 500] {
            let data = response("[{\"start_date\":\"2026-10-08\",\"tokens\":\(tokens)}]")
            for credentialScope in ["hash-personal", "hash-work"] {
                let history = try #require(try CodexTokenHistory.decode(data, scopeID: credentialScope))
                #expect(history.attribution == .unverifiedProfile)
                for workspace in [nil, "", "personal", "work"] as [String?] {
                    #expect(!history.isAttributed(toWorkspaceID: workspace))
                }
            }
        }
        let empty = try #require(try CodexTokenHistory.decode(response("[]"), scopeID: "hash-work"))
        #expect(!empty.isAttributed(toWorkspaceID: "work"))
    }

    @Test func explicitProviderAttributionMustMatchExpectedWorkspace() {
        let history = CodexTokenHistory(tokensByDate: ["2026-10-08": 0], fetchedAt: .now,
                                        scopeID: "credential-hash", attribution: .verifiedWorkspace("work"))
        #expect(history.isAttributed(toWorkspaceID: "work"))
        for workspace in [nil, "", "personal"] as [String?] {
            #expect(!history.isAttributed(toWorkspaceID: workspace))
        }
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
