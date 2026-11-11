import Foundation
import Testing
@testable import MobileAccessCore

@Test(arguments: [99.0, 99.4, 99.5, 99.99, 99.999999])
func remainingCapacityNeverReadsAsExhausted(percent: Double) {
    #expect(usagePercentForDisplay(percent) == 99)
    #expect(QuotaWindow(usedPercent: percent, durationSeconds: 18000, resetsAt: nil).displayPercent == 99)
}

@Test(arguments: [100.0, 101.0, 125.0])
func reachedLimitsKeepTheirPercentages(percent: Double) {
    #expect(usagePercentForDisplay(percent) == Int(percent))
}

@Test func ordinaryPercentagesRoundToNearest() {
    #expect(usagePercentForDisplay(0) == 0)
    #expect(usagePercentForDisplay(21.4) == 21)
    #expect(usagePercentForDisplay(21.6) == 22)
    #expect(usagePercentForDisplay(.nan) == 0)
}

@Test func budgetsReadNinetyNineUntilSpent() throws {
    let nearly = try #require(MonthlyBudget(used: 199.32, limit: 200, unit: "USD"))
    #expect(nearly.displayPercent == 99)
    let spent = try #require(MonthlyBudget(used: 200, limit: 200, unit: "USD"))
    #expect(spent.displayPercent == 100)
}
