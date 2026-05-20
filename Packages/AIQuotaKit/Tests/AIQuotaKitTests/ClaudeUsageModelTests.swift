import Foundation
import Testing
@testable import AIQuotaKit

@Suite("ClaudeUsage model")
struct ClaudeUsageModelTests {
    @Test("primary metric prefers 5-hour, then 7-day, then spend limit")
    func primaryMetricPrecedence() {
        let reset5h = Date(timeIntervalSince1970: 1_800)
        let reset7d = Date(timeIntervalSince1970: 86_400)
        let usage = ClaudeUsage(
            fiveHourUtilization: 42,
            fiveHourResetsAt: reset5h,
            sevenDayUtilization: 73,
            sevenDayResetsAt: reset7d,
            extraUsage: nil,
            spendLimit: .init(used: 80, limit: 100, utilization: 80),
            planLabel: .enterprise,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(usage.primaryMetric.kind == .fiveHour)
        #expect(usage.primaryMetric.utilization == 42)
        #expect(usage.primaryMetric.resetAt == reset5h)
        #expect(usage.usedPercent == 42)
    }

    @Test("seven-day wins when 5-hour window is absent")
    func sevenDayPrimaryWhenFiveHourMissing() {
        let reset7d = Date(timeIntervalSince1970: 86_400)
        let usage = ClaudeUsage(
            fiveHourUtilization: nil,
            fiveHourResetsAt: nil,
            sevenDayUtilization: 64,
            sevenDayResetsAt: reset7d,
            extraUsage: nil,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(usage.primaryMetric.kind == .sevenDay)
        #expect(usage.primaryMetric.resetAt == reset7d)
        #expect(usage.planLabel == .pro)
    }

    @Test("spend limit is distinct from Max extra usage")
    func spendLimitAndExtraUsageStayDistinct() {
        let enterprise = ClaudeUsage(
            fiveHourUtilization: nil,
            fiveHourResetsAt: nil,
            sevenDayUtilization: nil,
            sevenDayResetsAt: nil,
            extraUsage: nil,
            spendLimit: .init(used: 120, limit: 300, utilization: 40, currencyCode: "USD"),
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        let max = ClaudeUsage(
            fiveHourUtilization: 20,
            fiveHourResetsAt: Date(timeIntervalSince1970: 1_800),
            sevenDayUtilization: 25,
            sevenDayResetsAt: Date(timeIntervalSince1970: 86_400),
            extraUsage: .init(isEnabled: true, monthlyLimit: 2000, usedCredits: 100, utilization: 5),
            fetchedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(enterprise.primaryMetric.kind == .spendLimit)
        #expect(enterprise.planLabel == .enterprise)
        #expect(enterprise.extraUsage == nil)
        #expect(max.spendLimit == nil)
        #expect(max.planLabel == .max)
    }

    @Test("missing all usage signals remains unknown")
    func allMissingUsageSignalsRemainUnknown() {
        let usage = ClaudeUsage(
            fiveHourUtilization: nil,
            fiveHourResetsAt: nil,
            sevenDayUtilization: nil,
            sevenDayResetsAt: nil,
            extraUsage: nil,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(usage.primaryMetric.kind == .unknown)
        #expect(usage.primaryMetric.utilization == nil)
        #expect(usage.resetAt == nil)
        #expect(usage.planLabel == .unknown)
    }

    @Test("Claude usage decoder tolerates nullable buckets and uses model weekly fallbacks")
    func decoderUsesModelSpecificWeeklyFallbacks() throws {
        let json = """
        {
          "five_hour": { "utilization": null, "resets_at": null },
          "seven_day": null,
          "seven_day_sonnet": {
            "utilization": 37,
            "resets_at": "2026-05-21T10:00:00.000Z"
          },
          "extra_usage": {
            "is_enabled": true,
            "monthly_limit": 2000,
            "used_credits": 741,
            "utilization": 37.05
          }
        }
        """

        let usage = try ClaudeClient._decodeUsageForTesting(
            Data(json.utf8),
            planLabel: .max,
            source: .oauth,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(usage.primaryMetric.kind == .sevenDay)
        #expect(usage.sevenDayUtilization == 37)
        #expect(usage.extraUsage?.monthlyLimit == 2000)
        #expect(usage.extraUsage?.usedCredits == 741)
        #expect(usage.planLabel == .max)
    }

    @Test("Claude Enterprise extra usage spend decodes cents as dollars")
    func enterpriseSpendLimitDecodesCentsAsDollars() throws {
        let json = """
        {
          "five_hour": null,
          "seven_day": null,
          "extra_usage": {
            "monthly_limit": 100000,
            "used_credits": 4132,
            "currency": "USD"
          }
        }
        """

        let usage = try ClaudeClient._decodeUsageForTesting(
            Data(json.utf8),
            planLabel: .enterprise,
            source: .web,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(usage.primaryMetric.kind == .spendLimit)
        #expect(usage.spendLimit?.used == 41.32)
        #expect(usage.spendLimit?.limit == 1000)
        #expect(usage.spendLimit?.currencyCode == "USD")
        #expect(usage.extraUsage == nil)
    }
}
