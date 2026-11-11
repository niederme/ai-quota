import Testing
@testable import AIQuotaKit

@Suite("Usage percentage display")
struct UsagePercentageTests {
    @Test("remaining budget never rounds up to exhausted", arguments: [199.0, 199.32, 199.99, 199.999999])
    func remainingBudget(used: Double) {
        #expect(UsagePercentage.roundedForDisplay(used / 200 * 100) == 99)
    }

    @Test("reached limits and overages retain their percentages", arguments: [100.0, 101.0, 125.0])
    func reachedLimit(percent: Double) {
        #expect(UsagePercentage.roundedForDisplay(percent) == Int(percent))
    }

    @Test("ordinary percentages keep nearest-integer rounding")
    func ordinaryRounding() {
        #expect(UsagePercentage.roundedForDisplay(0) == 0)
        #expect(UsagePercentage.roundedForDisplay(21.4) == 21)
        #expect(UsagePercentage.roundedForDisplay(21.6) == 22)
    }

    @Test("Claude labels agree with the unrounded limit state", arguments: [199.32, 200, 201])
    func claudeSpendLimit(used: Double) {
        let usage = ClaudeUsage(
            fiveHourUtilization: nil, fiveHourResetsAt: nil,
            sevenDayUtilization: nil, sevenDayResetsAt: nil,
            extraUsage: nil,
            spendLimit: .init(used: used, limit: 200, utilization: used / 200 * 100),
            fetchedAt: .now
        )
        #expect((usage.usedPercent >= 100) == usage.limitReached)
        #expect(usage.usedPercent == (used < 200 ? 99 : Int((used / 200 * 100).rounded())))
    }
}
