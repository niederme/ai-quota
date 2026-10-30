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

    @Test func sustainedGrowthStillSeparatesOrdinaryDaysFromPeaks() {
        let recent = (1...90).map(Double.init)
        var tokens = history(recent)
        // A long, very quiet earlier period must not put every recent day at max.
        for offset in -364 ..< -90 { tokens[key(offset)] = 0.01 }
        let scale = CodexTokenActivityScale(tokensByDate: tokens, now: now)
        let levels = recent.map { scale.positiveLevel(for: $0) }
        #expect(scale.sampleCount == 90)
        #expect((0...3).map { level in levels.filter { $0 == level }.count } == [45, 27, 13, 5])
        #expect(scale.positiveLevel(for: 0.01) == 0)
        #expect(scale.positiveLevel(for: 100) == 3)
    }

    @Test func referenceWindowUsesCompletedUTCDaysOnly() {
        var tokens = [key(-91): 1e12, key(-90): 10, key(-1): 20,
                      key(0): 1e12, key(1): 1e12, key(-5): 0,
                      key(-6): -10, key(-7): Double.infinity, "2026-02-30": 1e12]
        let scale = CodexTokenActivityScale(tokensByDate: tokens, now: now.addingTimeInterval(23 * 3600))
        #expect(scale.sampleCount == 2)
        tokens.removeValue(forKey: key(0))
        let withoutToday = CodexTokenActivityScale(tokensByDate: tokens, now: now)
        #expect((1...25).allSatisfy { scale.positiveLevel(for: Double($0)) == withoutToday.positiveLevel(for: Double($0)) })
        // Once UTC midnight passes, the former partial day becomes eligible.
        let tomorrow = CodexTokenActivityScale(tokensByDate: [key(0): 10], now: now.addingTimeInterval(86400))
        #expect(tomorrow.sampleCount == 1)
    }

    @Test func exactBoundariesStayInTheLowerBand() {
        // 21 distinct samples put the interpolated cutoffs exactly at 11, 17, 20.
        let scale = CodexTokenActivityScale(tokensByDate: history((1...21).map(Double.init)), now: now)
        #expect([11, 11.1, 17, 17.1, 20, 20.1].map { scale.positiveLevel(for: $0) } == [0, 1, 1, 2, 2, 3])
    }

    @Test func tiesAndSparseHistoryDoNotInventBrightActivity() {
        for values in [[Double](), [100], Array(repeating: 100.0, count: 90)] {
            let scale = CodexTokenActivityScale(tokensByDate: history(values), now: now)
            #expect(scale.sampleCount == values.count)
            #expect(scale.positiveLevel(for: 100) == 0)
        }
        let todayOnly = CodexTokenActivityScale(tokensByDate: [key(0): 100], now: now)
        #expect(todayOnly.positiveLevel(for: 100) == 0)
        let tied = CodexTokenActivityScale(tokensByDate: history(Array(repeating: 10, count: 85) + Array(repeating: 20, count: 5)), now: now)
        #expect(tied.positiveLevel(for: 10) == 0)
        #expect(tied.positiveLevel(for: 20) == 3)
    }

    @Test func oneOutlierDoesNotWashOutTheRestAndAccountsStayIndependent() {
        let regular = history((1...89).map(Double.init) + [90])
        let outlier = history((1...89).map(Double.init) + [1e12])
        let first = CodexTokenActivityScale(tokensByDate: regular, now: now)
        let second = CodexTokenActivityScale(tokensByDate: outlier, now: now)
        #expect((1...89).allSatisfy { first.positiveLevel(for: Double($0)) == second.positiveLevel(for: Double($0)) })
        let heavyAccount = CodexTokenActivityScale(tokensByDate: history((1...90).map { Double($0) * 1000 }), now: now)
        #expect(first.positiveLevel(for: 90) == 3)
        #expect(heavyAccount.positiveLevel(for: 90) == 0)
    }
}
