import Foundation

// MARK: - Display model

/// Quota / rate-limit data for a Claude account.
///
/// Populated from GET /api/organizations/{org_uuid}/usage on claude.ai.
/// The API returns utilization percentages (0–100), not message counts.
/// There are two independent rolling windows:
///   • **five_hour** — the primary short-term rate-limit gate (≈ 5 hours)
///   • **seven_day** — a secondary longer-term gate (7 days)
///
/// Max-plan accounts also receive an `extra_usage` bucket showing monthly
/// credit consumption for overflow / API-based usage.
public struct ClaudeUsage: Codable, Sendable, Equatable {

    // MARK: - Five-hour window (primary rate-limit)

    /// Percentage of the 5-hour rolling window consumed, 0–100.
    public let fiveHourUtilization: Double
    /// When the 5-hour window resets.
    public let fiveHourResetsAt: Date

    // MARK: - Seven-day window (secondary gate)

    /// Percentage of the 7-day rolling window consumed, 0–100.
    public let sevenDayUtilization: Double
    /// When the 7-day window resets.
    public let sevenDayResetsAt: Date

    // MARK: - Extra usage / credits (Max plans)

    /// Overflow credit usage, present and enabled on Max plans.
    public let extraUsage: ExtraUsage?

    public let fetchedAt: Date

    // MARK: - Nested types

    public struct ExtraUsage: Codable, Sendable, Equatable {
        /// Whether the extra-usage credits bucket is active for this account.
        public let isEnabled: Bool
        /// Monthly credit ceiling (e.g. 2000).
        public let monthlyLimit: Int
        /// Credits consumed so far this month.
        public let usedCredits: Double
        /// Percentage of monthly credits consumed, 0–100.
        public let utilization: Double
    }

    // MARK: - Computed (gauge / notification compatibility)

    /// Primary gauge value: 5-hour utilization rounded to an integer, 0–100.
    public var usedPercent: Int { Int(fiveHourUtilization.rounded()) }

    /// `true` when the 5-hour window is fully exhausted (≥ 100%).
    public var limitReached: Bool { fiveHourUtilization >= 100 }

    /// Fraction 0–1 for use in SwiftUI `Gauge` views.
    public var percentFraction: Double { (fiveHourUtilization / 100.0).clamped(to: 0...1) }

    /// Percentage of the 5-hour window's capacity still available.
    public var remainingPercent: Int { max(0, 100 - usedPercent) }

    /// Alias for callers that reference `resetAt` (e.g. NotificationManager).
    public var resetAt: Date { fiveHourResetsAt }

    /// Seconds until the 5-hour window resets, clamped to ≥ 0.
    public var resetAfterSeconds: Int { max(0, Int(fiveHourResetsAt.timeIntervalSinceNow)) }

    /// Seconds until the 7-day window resets, clamped to ≥ 0.
    public var sevenDayResetAfterSeconds: Int { max(0, Int(sevenDayResetsAt.timeIntervalSinceNow)) }

    /// Human-readable plan label inferred from response fields.
    /// The /usage endpoint does not return a plan name; we infer from
    /// the presence of `extra_usage` (a Max-plan feature) vs. absence (Pro).
    public var planDisplayName: String {
        extraUsage?.isEnabled == true ? "Max" : "Pro"
    }

    // MARK: - Init

    public init(
        fiveHourUtilization: Double,
        fiveHourResetsAt: Date,
        sevenDayUtilization: Double,
        sevenDayResetsAt: Date,
        extraUsage: ExtraUsage?,
        fetchedAt: Date
    ) {
        self.fiveHourUtilization = fiveHourUtilization
        self.fiveHourResetsAt    = fiveHourResetsAt
        self.sevenDayUtilization = sevenDayUtilization
        self.sevenDayResetsAt    = sevenDayResetsAt
        self.extraUsage          = extraUsage
        self.fetchedAt           = fetchedAt
    }

    // MARK: - Placeholder / preview

    public static let placeholder = ClaudeUsage(
        fiveHourUtilization: 34,
        fiveHourResetsAt: Date.now.addingTimeInterval(14_400),
        sevenDayUtilization: 30,
        sevenDayResetsAt: Date.now.addingTimeInterval(86_400 * 5),
        extraUsage: ExtraUsage(
            isEnabled: true, monthlyLimit: 2000,
            usedCredits: 1609, utilization: 80.45
        ),
        fetchedAt: .now
    )

    public static let exhausted = ClaudeUsage(
        fiveHourUtilization: 100,
        fiveHourResetsAt: Date.now.addingTimeInterval(3_600),
        sevenDayUtilization: 75,
        sevenDayResetsAt: Date.now.addingTimeInterval(86_400 * 2),
        extraUsage: nil,
        fetchedAt: .now
    )
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
