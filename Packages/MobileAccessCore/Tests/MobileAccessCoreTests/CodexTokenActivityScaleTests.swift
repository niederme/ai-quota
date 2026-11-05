import Foundation
import Testing
@testable import MobileAccessCore

struct CodexTokenActivityScaleTests {
    private let now = CodexTokenHistory.dateFormatter().date(from: "2026-10-30")!

    private func key(_ offset: Int) -> String {
        CodexTokenHistory.dateFormatter().string(from: CodexTokenHistory.calendar.date(byAdding: .day, value: offset, to: now)!)
    }

    private func history(_ values: [Double]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: values.enumerated().map { (key($0.offset - values.count), $0.element) })
    }

    @Test func stepsAreLogarithmicBelowTheBigDay() {
        // Fewer than ten days: the busiest day is the big day.
        let scale = CodexTokenActivityScale(tokensByDate: history([1_000, 30_000]), now: now)
        #expect(scale.reference == 30_000)
        // Span is 1/30 of the big day (1,000) up to it; each step is 30^(1/4) ≈ 2.34×.
        // Step edges: 1,000 × 30^(k/4) ≈ 2,340, 5,477 and 12,819.
        #expect([500, 1_000, 1_100, 2_400, 5_600, 12_000, 13_000, 29_999, 30_000, 1e9]
            .map { scale.positiveLevel(for: $0) } == [0, 0, 0, 1, 2, 2, 3, 3, 3, 3])
    }

    @Test func bigDayIsTheNinetiethPercentileOnceThereAreTenDays() {
        // 11 days: the 90th percentile interpolates to exactly 100.
        let values = (1...10).map { Double($0) * 10 } + [10_000]
        let scale = CodexTokenActivityScale(tokensByDate: history(values), now: now)
        #expect(scale.sampleCount == 11)
        #expect(scale.reference == 100)
        // One outlier does not wash out the other days.
        #expect(scale.positiveLevel(for: 100) == 3)
        #expect(scale.positiveLevel(for: 10_000) == 3)
        #expect(scale.positiveLevel(for: 10) == 1)
    }

    @Test func baselineCoversTheYearAndUsesCompletedUTCDaysOnly() {
        var tokens = [key(-365): 1e12, key(-300): 10, key(-1): 20,
                      key(0): 1e12, key(1): 1e12, key(-5): 0,
                      key(-6): -10, key(-7): Double.infinity, "2026-02-30": 1e12]
        let scale = CodexTokenActivityScale(tokensByDate: tokens, now: now.addingTimeInterval(23 * 3600))
        #expect(scale.sampleCount == 2)
        #expect(scale.reference == 20)
        tokens.removeValue(forKey: key(0))
        let withoutToday = CodexTokenActivityScale(tokensByDate: tokens, now: now)
        #expect(withoutToday.reference == scale.reference)
        // Once UTC midnight passes, the former partial day becomes eligible.
        let tomorrow = CodexTokenActivityScale(tokensByDate: [key(0): 10], now: now.addingTimeInterval(86400))
        #expect(tomorrow.sampleCount == 1)
    }

    @Test func newAccountsUseTheirOwnDaysWithNoAbsoluteFloor() {
        // A brand-new account with a few small days still spreads across all steps.
        let scale = CodexTokenActivityScale(tokensByDate: history([40_000, 180_000, 900_000, 2_400_000, 6_000_000]), now: now)
        #expect(([40_000, 180_000, 900_000, 2_400_000, 6_000_000] as [Double]).map { scale.positiveLevel(for: $0) } == [0, 0, 1, 2, 3])
        let empty = CodexTokenActivityScale(tokensByDate: [:], now: now)
        #expect(empty.reference == nil)
        #expect(empty.positiveLevel(for: 100) == 0)
        let todayOnly = CodexTokenActivityScale(tokensByDate: [key(0): 100], now: now)
        #expect(todayOnly.positiveLevel(for: 100) == 0)
    }

    @Test func accountsStayIndependent() {
        let light = CodexTokenActivityScale(tokensByDate: history((1...90).map(Double.init)), now: now)
        let heavy = CodexTokenActivityScale(tokensByDate: history((1...90).map { Double($0) * 1000 }), now: now)
        #expect(light.positiveLevel(for: 90) == 3)
        #expect(heavy.positiveLevel(for: 90) == 0)
        #expect(heavy.positiveLevel(for: 90_000) == 3)
    }
}
