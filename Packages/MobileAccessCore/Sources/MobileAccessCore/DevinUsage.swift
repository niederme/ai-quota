import Foundation

/// A single Devin quota reading decoded from the seat-management `GetUserStatus`
/// response — the same call the Devin CLI and desktop app make.
///
/// Devin reports *remaining* percentages for a daily and a weekly window; this
/// model stores *used* percentages to match the rest of the app.
public struct DevinUsage: Codable, Sendable, Equatable {
    public let dailyUsedPercent: Double?
    public let dailyResetsAt: Date?
    public let weeklyUsedPercent: Double?
    public let weeklyResetsAt: Date?
    public let planName: String?
    public let accountDisplayName: String?
    /// Remaining on-demand balance in dollars (`overage_balance_micros` / 1e6).
    public let overageBalanceUSD: Double?
    public let planStart: Date?
    public let planEnd: Date?
    public let source: Source
    public let fetchedAt: Date

    public enum Source: String, Codable, Sendable, Equatable {
        /// `credentials.toml` written by `devin auth login` (Devin CLI).
        case cli
        /// `state.vscdb` inside the Devin desktop app's Application Support data.
        case appState
        /// A session token the user pasted into Settings.
        case manual
        case unknown
    }

    public enum DisplayKind: String, Codable, Sendable, Equatable {
        case daily
        case weekly
        case unknown

        public var displayLabel: String {
            switch self {
            case .daily: "1d"
            case .weekly: "7d"
            case .unknown: "Usage"
            }
        }
    }

    public struct Metric: Codable, Sendable, Equatable {
        public let kind: DisplayKind
        public let utilization: Double?
        public let resetAt: Date?

        public init(kind: DisplayKind, utilization: Double?, resetAt: Date?) {
            self.kind = kind
            self.utilization = utilization
            self.resetAt = resetAt
        }

        public var displayLabel: String { kind.displayLabel }
    }

    public var primaryMetric: Metric {
        if let dailyUsedPercent {
            return Metric(kind: .daily, utilization: dailyUsedPercent, resetAt: dailyResetsAt)
        }
        if let weeklyUsedPercent {
            return Metric(kind: .weekly, utilization: weeklyUsedPercent, resetAt: weeklyResetsAt)
        }
        return Metric(kind: .unknown, utilization: nil, resetAt: nil)
    }

    public var usedPercent: Int { Int((primaryMetric.utilization ?? 0).rounded()) }
    public var limitReached: Bool { (primaryMetric.utilization ?? 0) >= 100 }
    public var percentFraction: Double { min(1, max(0, (primaryMetric.utilization ?? 0) / 100.0)) }
    public var remainingPercent: Int { max(0, 100 - usedPercent) }
    public var resetAt: Date? { primaryMetric.resetAt }
    public var resetAfterSeconds: Int? { primaryMetric.resetAt.map { max(0, Int($0.timeIntervalSinceNow)) } }
    public var weeklyResetAfterSeconds: Int? { weeklyResetsAt.map { max(0, Int($0.timeIntervalSinceNow)) } }
    public var planDisplayName: String { planName ?? "Unknown" }
    public var hasDailyWindow: Bool { dailyUsedPercent != nil }
    public var hasWeeklyWindow: Bool { weeklyUsedPercent != nil }
    public var primaryMetricLabel: String { primaryMetric.displayLabel }

    public init(
        dailyUsedPercent: Double?,
        dailyResetsAt: Date?,
        weeklyUsedPercent: Double?,
        weeklyResetsAt: Date?,
        planName: String? = nil,
        accountDisplayName: String? = nil,
        overageBalanceUSD: Double? = nil,
        planStart: Date? = nil,
        planEnd: Date? = nil,
        source: Source = .unknown,
        fetchedAt: Date
    ) {
        self.dailyUsedPercent = dailyUsedPercent
        self.dailyResetsAt = dailyResetsAt
        self.weeklyUsedPercent = weeklyUsedPercent
        self.weeklyResetsAt = weeklyResetsAt
        self.planName = planName
        self.accountDisplayName = accountDisplayName
        self.overageBalanceUSD = overageBalanceUSD
        self.planStart = planStart
        self.planEnd = planEnd
        self.source = source
        self.fetchedAt = fetchedAt
    }

    public static let placeholder = DevinUsage(
        dailyUsedPercent: 34,
        dailyResetsAt: Date.now.addingTimeInterval(14_400),
        weeklyUsedPercent: 30,
        weeklyResetsAt: Date.now.addingTimeInterval(86_400 * 5),
        planName: "Pro",
        accountDisplayName: "Personal",
        source: .cli,
        fetchedAt: .now
    )
}
