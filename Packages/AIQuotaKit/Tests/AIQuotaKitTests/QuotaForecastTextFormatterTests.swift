import Foundation
import Testing
@testable import AIQuotaKit

struct QuotaForecastTextFormatterTests {
    @Test func copyDistinguishesPatternAndAverageWithoutAnExhaustionTime() {
        let scope = QuotaForecastScope(accountID: "sample", provider: "codex", identity: "workspace", source: "wham", plan: "pro",
            window: .weekly, resetAt: .now.addingTimeInterval(4 * 86400))
        for basis in [QuotaExhaustionForecast.Basis.weeklyPattern, .periodAverage] {
            let value = QuotaExhaustionForecast(scope: scope, basis: basis, projectedUsedPercent: 140,
                                               validUntil: .now.addingTimeInterval(3600))
            let text = QuotaForecastTextFormatter.detail(value)
            #expect(text.contains(basis == .weeklyPattern ? "usual weekly pattern" : "average pace this period"))
            #expect(text.contains("Resets"))
            #expect(!text.contains("Around") && !text.contains("recent pace"))
        }
    }
}
