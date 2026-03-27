import XCTest
@testable import AIQuotaKit

final class WidgetRefreshPolicyTests: XCTestCase {
    func testShouldFetchFromNetworkWhenNoCachedDataExists() {
        XCTAssertTrue(WidgetRefreshPolicy.shouldFetchFromNetwork(codex: nil, claude: nil, now: now))
    }

    func testShouldNotFetchFromNetworkWhenCacheIsFresh() throws {
        let codex = try makeCodexUsage(
            fetchedAt: now.addingTimeInterval(-240),
            hourlyResetAt: now.addingTimeInterval(7_200),
            weeklyResetAt: now.addingTimeInterval(172_800)
        )

        XCTAssertFalse(WidgetRefreshPolicy.shouldFetchFromNetwork(codex: codex, claude: nil, now: now))
    }

    func testShouldFetchFromNetworkWhenNewestCacheIsOlderThanFiveMinutes() throws {
        let claude = try makeClaudeUsage(
            fetchedAt: now.addingTimeInterval(-301),
            fiveHourResetsAt: now.addingTimeInterval(7_200),
            sevenDayResetsAt: now.addingTimeInterval(172_800)
        )

        XCTAssertTrue(WidgetRefreshPolicy.shouldFetchFromNetwork(codex: nil, claude: claude, now: now))
    }

    func testNextTimelineDateUsesOneMinuteFloorWhenNoDataExists() {
        let next = WidgetRefreshPolicy.nextTimelineDate(codex: nil, claude: nil, now: now)
        XCTAssertEqual(next.timeIntervalSince(now), 60, accuracy: 0.5)
    }

    func testNextTimelineDateUsesFiveMinuteHeartbeatWhenResetsAreFarAway() throws {
        let codex = try makeCodexUsage(
            fetchedAt: now,
            hourlyResetAt: now.addingTimeInterval(7_200),
            weeklyResetAt: now.addingTimeInterval(172_800)
        )

        let next = WidgetRefreshPolicy.nextTimelineDate(codex: codex, claude: nil, now: now)
        XCTAssertEqual(next.timeIntervalSince(now), 300, accuracy: 0.5)
    }

    func testNextTimelineDatePrefersSoonerResetBoundaryOverHeartbeat() throws {
        let claude = try makeClaudeUsage(
            fetchedAt: now,
            fiveHourResetsAt: now.addingTimeInterval(90),
            sevenDayResetsAt: now.addingTimeInterval(172_800)
        )

        let next = WidgetRefreshPolicy.nextTimelineDate(codex: nil, claude: claude, now: now)
        XCTAssertEqual(next.timeIntervalSince(now), 90, accuracy: 0.5)
    }

    private let now = Date(timeIntervalSince1970: 1_743_076_800)

    private func makeCodexUsage(
        fetchedAt: Date,
        hourlyResetAt: Date,
        weeklyResetAt: Date
    ) throws -> CodexUsage {
        let json = """
        {
          "weeklyUsedPercent": 62,
          "weeklyResetAt": "\(iso(weeklyResetAt))",
          "weeklyResetAfterSeconds": \(Int(weeklyResetAt.timeIntervalSince(now))),
          "hourlyUsedPercent": 19,
          "hourlyResetAt": "\(iso(hourlyResetAt))",
          "hourlyResetAfterSeconds": \(Int(hourlyResetAt.timeIntervalSince(now))),
          "hourlyWindowSeconds": 18000,
          "limitReached": false,
          "allowed": true,
          "planType": "plus",
          "creditBalance": 100.0,
          "approxLocalMessages": [30, 256],
          "approxCloudMessages": [5, 49],
          "fetchedAt": "\(iso(fetchedAt))"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CodexUsage.self, from: Data(json.utf8))
    }

    private func makeClaudeUsage(
        fetchedAt: Date,
        fiveHourResetsAt: Date,
        sevenDayResetsAt: Date
    ) throws -> ClaudeUsage {
        let json = """
        {
          "fiveHourUtilization": 24.0,
          "fiveHourResetsAt": "\(iso(fiveHourResetsAt))",
          "sevenDayUtilization": 44.0,
          "sevenDayResetsAt": "\(iso(sevenDayResetsAt))",
          "extraUsage": null,
          "fetchedAt": "\(iso(fetchedAt))"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClaudeUsage.self, from: Data(json.utf8))
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
