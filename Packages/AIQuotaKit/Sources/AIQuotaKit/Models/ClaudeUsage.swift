import Foundation

public struct ClaudeUsage: Codable, Sendable, Equatable {
    public let fiveHourUtilization: Double?
    public let fiveHourResetsAt: Date?
    public let sevenDayUtilization: Double?
    public let sevenDayResetsAt: Date?
    public let extraUsage: ExtraUsage?
    public let spendLimit: SpendLimit?
    public let planLabel: PlanLabel
    public let primaryMetric: Metric
    public let source: Source
    public let fetchedAt: Date

    public enum DisplayKind: String, Codable, Sendable, Equatable {
        case fiveHour
        case sevenDay
        case spendLimit
        case unknown

        public var displayLabel: String {
            switch self {
            case .fiveHour: "5h"
            case .sevenDay: "7d"
            case .spendLimit: "Spend"
            case .unknown: "Usage"
            }
        }
    }

    public enum PlanLabel: String, Codable, Sendable, Equatable {
        case pro
        case max
        case team
        case enterprise
        case ultra
        case unknown

        public var displayName: String {
            switch self {
            case .pro: "Pro"
            case .max: "Max"
            case .team: "Team"
            case .enterprise: "Enterprise"
            case .ultra: "Ultra"
            case .unknown: "Unknown"
            }
        }
    }

    public enum Source: String, Codable, Sendable, Equatable {
        case web
        case oauth
        case unknown
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

    public struct ExtraUsage: Codable, Sendable, Equatable {
        public let isEnabled: Bool
        public let monthlyLimit: Int
        public let usedCredits: Double
        public let utilization: Double

        public init(isEnabled: Bool, monthlyLimit: Int, usedCredits: Double, utilization: Double) {
            self.isEnabled = isEnabled
            self.monthlyLimit = monthlyLimit
            self.usedCredits = usedCredits
            self.utilization = utilization
        }
    }

    public struct SpendLimit: Codable, Sendable, Equatable {
        public let used: Double
        public let limit: Double
        public let utilization: Double
        public let currencyCode: String?

        public init(used: Double, limit: Double, utilization: Double, currencyCode: String? = nil) {
            self.used = used
            self.limit = limit
            self.utilization = utilization
            self.currencyCode = currencyCode
        }
    }

    public var usedPercent: Int { Int((primaryMetric.utilization ?? 0).rounded()) }
    public var limitReached: Bool { (primaryMetric.utilization ?? 0) >= 100 }
    public var percentFraction: Double { ((primaryMetric.utilization ?? 0) / 100.0).clamped(to: 0...1) }
    public var remainingPercent: Int { max(0, 100 - usedPercent) }
    public var resetAt: Date? { primaryMetric.resetAt }
    public var resetAfterSeconds: Int? { primaryMetric.resetAt.map { max(0, Int($0.timeIntervalSinceNow)) } }
    public var sevenDayResetAfterSeconds: Int? { sevenDayResetsAt.map { max(0, Int($0.timeIntervalSinceNow)) } }
    public var planDisplayName: String { planLabel.displayName }
    public var hasFiveHourWindow: Bool { fiveHourUtilization != nil && fiveHourResetsAt != nil }
    public var hasSevenDayWindow: Bool { sevenDayUtilization != nil && sevenDayResetsAt != nil }
    public var primaryMetricLabel: String { primaryMetric.displayLabel }

    public init(
        fiveHourUtilization: Double?,
        fiveHourResetsAt: Date?,
        sevenDayUtilization: Double?,
        sevenDayResetsAt: Date?,
        extraUsage: ExtraUsage?,
        spendLimit: SpendLimit? = nil,
        planLabel: PlanLabel? = nil,
        source: Source = .unknown,
        fetchedAt: Date
    ) {
        self.fiveHourUtilization = fiveHourUtilization
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayUtilization = sevenDayUtilization
        self.sevenDayResetsAt = sevenDayResetsAt
        self.extraUsage = extraUsage
        self.spendLimit = spendLimit
        self.planLabel = planLabel ?? Self.inferPlanLabel(
            extraUsage: extraUsage,
            spendLimit: spendLimit,
            hasWindowUsage: fiveHourUtilization != nil || sevenDayUtilization != nil
        )
        self.primaryMetric = Self.makePrimaryMetric(
            fiveHourUtilization: fiveHourUtilization,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayUtilization: sevenDayUtilization,
            sevenDayResetsAt: sevenDayResetsAt,
            spendLimit: spendLimit
        )
        self.source = source
        self.fetchedAt = fetchedAt
    }

    public static func makePrimaryMetric(
        fiveHourUtilization: Double?,
        fiveHourResetsAt: Date?,
        sevenDayUtilization: Double?,
        sevenDayResetsAt: Date?,
        spendLimit: SpendLimit?
    ) -> Metric {
        if let fiveHourUtilization {
            return Metric(kind: .fiveHour, utilization: fiveHourUtilization, resetAt: fiveHourResetsAt)
        }
        if let sevenDayUtilization {
            return Metric(kind: .sevenDay, utilization: sevenDayUtilization, resetAt: sevenDayResetsAt)
        }
        if let spendLimit {
            return Metric(kind: .spendLimit, utilization: spendLimit.utilization, resetAt: nil)
        }
        return Metric(kind: .unknown, utilization: nil, resetAt: nil)
    }

    public static func inferPlanLabel(
        extraUsage: ExtraUsage?,
        spendLimit: SpendLimit?,
        hasWindowUsage: Bool = true
    ) -> PlanLabel {
        if spendLimit != nil { return .enterprise }
        if extraUsage?.isEnabled == true { return .max }
        if !hasWindowUsage { return .unknown }
        return .pro
    }

    public static let placeholder = ClaudeUsage(
        fiveHourUtilization: 34,
        fiveHourResetsAt: Date.now.addingTimeInterval(14_400),
        sevenDayUtilization: 30,
        sevenDayResetsAt: Date.now.addingTimeInterval(86_400 * 5),
        extraUsage: ExtraUsage(
            isEnabled: true,
            monthlyLimit: 2000,
            usedCredits: 1609,
            utilization: 80.45
        ),
        planLabel: .max,
        fetchedAt: .now
    )

    public static let exhausted = ClaudeUsage(
        fiveHourUtilization: 100,
        fiveHourResetsAt: Date.now.addingTimeInterval(3_600),
        sevenDayUtilization: 75,
        sevenDayResetsAt: Date.now.addingTimeInterval(86_400 * 2),
        extraUsage: nil,
        planLabel: .pro,
        fetchedAt: .now
    )

    enum CodingKeys: String, CodingKey {
        case fiveHourUtilization
        case fiveHourResetsAt
        case sevenDayUtilization
        case sevenDayResetsAt
        case extraUsage
        case spendLimit
        case planLabel
        case source
        case fetchedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fiveHourUtilization = try container.decodeIfPresent(Double.self, forKey: .fiveHourUtilization)
        let fiveHourResetsAt = try container.decodeIfPresent(Date.self, forKey: .fiveHourResetsAt)
        let sevenDayUtilization = try container.decodeIfPresent(Double.self, forKey: .sevenDayUtilization)
        let sevenDayResetsAt = try container.decodeIfPresent(Date.self, forKey: .sevenDayResetsAt)
        let extraUsage = try container.decodeIfPresent(ExtraUsage.self, forKey: .extraUsage)
        let spendLimit = try container.decodeIfPresent(SpendLimit.self, forKey: .spendLimit)
        let planLabel = try container.decodeIfPresent(PlanLabel.self, forKey: .planLabel)
        let source = try container.decodeIfPresent(Source.self, forKey: .source) ?? .unknown
        let fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        self.init(
            fiveHourUtilization: fiveHourUtilization,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayUtilization: sevenDayUtilization,
            sevenDayResetsAt: sevenDayResetsAt,
            extraUsage: extraUsage,
            spendLimit: spendLimit,
            planLabel: planLabel,
            source: source,
            fetchedAt: fetchedAt
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
