import Foundation
import Testing
@testable import AIQuotaKit

@Suite("Compact reported quota shape")
struct CompactWindowShapeTests {
    private func decode(_ windows: String) throws -> CodexUsage {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = try decoder.decode(WhamUsageResponse.self, from: Data("{\"plan_type\":\"arbitrary\",\"rate_limit\":{\(windows)}}".utf8))
        return CodexUsage(from: raw, fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
    private let weekly = #"{"used_percent":56,"limit_window_seconds":604800,"reset_at":1800100000,"reset_after_seconds":100000}"#
    private let hourly = #"{"used_percent":22,"limit_window_seconds":18000,"reset_at":1800010000,"reset_after_seconds":10000}"#

    @Test func completedWeeklyPrimaryIsSingle() throws {
        let usage = try decode("\"primary_window\":\(weekly),\"secondary_window\":null")
        #expect(usage.reportsWeeklyOnlyWindow)
        #expect(usage.reportedWindowShape == .weeklyOnly)
        #expect(usage.weeklyUsedPercent == 56)
        #expect(usage.weeklyResetAfterSeconds == 100000)
        #expect(!usage.hasHourlyWindow)
        #expect(usage.withBonusCreditsSpentThisMonth(5).reportsWeeklyOnlyWindow)
        let cached = try JSONDecoder().decode(CodexUsage.self, from: JSONEncoder().encode(usage))
        #expect(cached == usage)
    }

    @Test func bothCompletedWindowsRemainDual() throws {
        let usage = try decode("\"primary_window\":\(hourly),\"secondary_window\":\(weekly)")
        #expect(usage.reportedWindowShape == .dual)
        #expect(!usage.reportsWeeklyOnlyWindow)
        #expect(usage.hourlyUsedPercent == 22)
    }

    @Test func missingAndPartialAreUnknownAndRetainConfirmedSnapshot() throws {
        let single = try decode("\"primary_window\":\(weekly),\"secondary_window\":null")
        let dual = try decode("\"primary_window\":\(hourly),\"secondary_window\":\(weekly)")
        for windows in [
            "", "\"primary_window\":null,\"secondary_window\":null",
            "\"primary_window\":\(weekly)",
            "\"primary_window\":\(weekly),\"secondary_window\":{}",
            #""primary_window":{"used_percent":null,"limit_window_seconds":604800,"reset_at":1800100000},"secondary_window":null"#,
            #""primary_window":{"used_percent":40,"limit_window_seconds":604800},"secondary_window":null"#,
            #""primary_window":{"used_percent":40,"limit_window_seconds":604800,"reset_at":1800100000},"secondary_window":null"#,
            #""primary_window":{"used_percent":-1,"limit_window_seconds":604800,"reset_at":1800100000},"secondary_window":null"#
        ] {
            let partial = try decode(windows)
            #expect(partial.reportedWindowShape == nil)
            #expect(!partial.reportsWeeklyOnlyWindow)
            #expect(partial.retainingLastConfirmedWindows(from: single) == single)
            #expect(partial.retainingLastConfirmedWindows(from: dual) == dual)
            #expect(partial.retainingLastConfirmedWindows(from: nil) == partial)
        }
    }

    @Test func validRefreshCanChangeShapeAndOldCacheRemainsUnknown() throws {
        let single = try decode("\"primary_window\":\(weekly),\"secondary_window\":null")
        let dual = try decode("\"primary_window\":\(hourly),\"secondary_window\":\(weekly)")
        #expect(single.retainingLastConfirmedWindows(from: dual) == single)
        #expect(dual.retainingLastConfirmedWindows(from: single) == dual)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(single)) as? [String: Any])
        json.removeValue(forKey: "reportedWindowShape")
        let old = try JSONDecoder().decode(CodexUsage.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.reportedWindowShape == nil)
        #expect(!old.reportsWeeklyOnlyWindow)
    }
}
