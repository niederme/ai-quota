import Foundation

// MARK: - Raw API response from GET https://chatgpt.com/backend-api/wham/usage

public struct WhamUsageResponse: Decodable, Sendable {
    public let userId: String?
    public let accountId: String?
    public let email: String?
    public let planType: String?
    public let rateLimit: RateLimitInfo?
    public let codeReviewRateLimit: RateLimitInfo?
    public let credits: Credits?

    public struct RateLimitInfo: Decodable, Sendable {
        public let allowed: Bool?
        public let limitReached: Bool?
        public let primaryWindow: Window?   // short window (~5h)
        public let secondaryWindow: Window? // weekly window (7 days)

        public struct Window: Decodable, Sendable {
            public let usedPercent: Int?
            public let limitWindowSeconds: Int?
            public let resetAfterSeconds: Int?
            public let resetAt: Int? // Unix timestamp

            private enum CodingKeys: String, CodingKey {
                case usedPercent
                case limitWindowSeconds
                case resetAfterSeconds
                case resetAt
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                usedPercent = try container.decodeLossyIntIfPresent(forKey: .usedPercent)
                limitWindowSeconds = try container.decodeLossyIntIfPresent(forKey: .limitWindowSeconds)
                resetAfterSeconds = try container.decodeLossyIntIfPresent(forKey: .resetAfterSeconds)
                resetAt = try container.decodeLossyIntIfPresent(forKey: .resetAt)
            }
        }
    }

    public struct Credits: Decodable, Sendable {
        public let hasCredits: Bool
        public let unlimited: Bool
        public let balance: String?
        // [current, limit] — e.g. [49, 256] means 49 of 256 used
        public let approxLocalMessages: [Int]?
        public let approxCloudMessages: [Int]?

        private enum CodingKeys: String, CodingKey {
            case hasCredits
            case unlimited
            case balance
            case approxLocalMessages
            case approxCloudMessages
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hasCredits = (try? container.decodeIfPresent(Bool.self, forKey: .hasCredits)) ?? false
            unlimited = (try? container.decodeIfPresent(Bool.self, forKey: .unlimited)) ?? false
            balance = try container.decodeLossyStringIfPresent(forKey: .balance)
            approxLocalMessages = try? container.decodeIfPresent([Int].self, forKey: .approxLocalMessages)
            approxCloudMessages = try? container.decodeIfPresent([Int].self, forKey: .approxCloudMessages)
        }
    }
}

// MARK: - Display model

public struct CodexUsage: Codable, Sendable, Equatable {
    // Weekly (secondary window, 604800s)
    public let weeklyUsedPercent: Int
    public let weeklyResetAt: Date
    public let weeklyResetAfterSeconds: Int

    // Short window (primary, typically 18000s = 5h)
    public let hourlyUsedPercent: Int
    public let hourlyResetAt: Date
    public let hourlyResetAfterSeconds: Int
    public let hourlyWindowSeconds: Int  // actual window size

    // Rate limit state
    public let limitReached: Bool
    public let allowed: Bool
    public let planType: String

    // Credits
    public let creditBalance: Double?
    public let bonusCreditsSpentThisMonth: Double?
    public let approxLocalMessages: [Int]?  // [used, limit]
    public let approxCloudMessages: [Int]?  // [used, limit]

    public let fetchedAt: Date

    // MARK: Computed

    public var weeklyPercentFraction: Double { Double(weeklyUsedPercent) / 100.0 }
    public var hourlyPercentFraction: Double { Double(hourlyUsedPercent) / 100.0 }
    public var weeklyRemaining: Int { max(0, 100 - weeklyUsedPercent) }
    public var isWeeklyExhausted: Bool { weeklyUsedPercent >= 100 }
    public var hasHourlyWindow: Bool { hourlyResetAt != .distantFuture }

    public var localMessagesUsed: Int? { approxLocalMessages?.first }
    public var localMessagesLimit: Int? { approxLocalMessages?.last }
    public var cloudMessagesUsed: Int? { approxCloudMessages?.first }
    public var cloudMessagesLimit: Int? { approxCloudMessages?.last }

    // MARK: Init from API response

    public init(from response: WhamUsageResponse, fetchedAt: Date = .now) {
        let rateLimit = response.rateLimit
        let primary = rateLimit?.primaryWindow
        let secondary = rateLimit?.secondaryWindow

        // Codex historically returned a short primary window and a weekly
        // secondary window. Some accounts now expose only the weekly window,
        // in primary_window. Normalize both response shapes so callers can
        // continue treating the weekly quota as weekly without inventing an
        // unavailable short-window metric.
        let primaryIsWeekly = secondary == nil && (primary?.limitWindowSeconds ?? 0) >= 6 * 86_400
        let weekly = secondary ?? (primaryIsWeekly ? primary : nil)
        let hourly = primaryIsWeekly ? nil : primary

        weeklyUsedPercent = weekly?.usedPercent ?? 0
        weeklyResetAt = weekly?.resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .distantFuture
        weeklyResetAfterSeconds = weekly?.resetAfterSeconds ?? 0

        hourlyUsedPercent = hourly?.usedPercent ?? 0
        hourlyResetAt = hourly?.resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .distantFuture
        hourlyResetAfterSeconds = hourly?.resetAfterSeconds ?? 0
        hourlyWindowSeconds = hourly?.limitWindowSeconds ?? 18000

        limitReached = rateLimit?.limitReached ?? false
        allowed = rateLimit?.allowed ?? true
        planType = response.planType ?? "unknown"

        creditBalance = response.credits?.balance.flatMap { Double($0) }
        bonusCreditsSpentThisMonth = nil
        approxLocalMessages = response.credits?.approxLocalMessages
        approxCloudMessages = response.credits?.approxCloudMessages

        self.fetchedAt = fetchedAt
    }

    // MARK: Placeholder / preview

    public static let placeholder = CodexUsage(
        weeklyUsedPercent: 62,
        weeklyResetAt: Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now,
        weeklyResetAfterSeconds: 3 * 86400,
        hourlyUsedPercent: 0,
        hourlyResetAt: Date.now.addingTimeInterval(3600),
        hourlyResetAfterSeconds: 3600,
        hourlyWindowSeconds: 18000,
        limitReached: false, allowed: true, planType: "plus",
        creditBalance: 197.18,
        bonusCreditsSpentThisMonth: 142.6,
        approxLocalMessages: [30, 256],
        approxCloudMessages: [5, 49],
        fetchedAt: .now
    )

    public static let exhausted = CodexUsage(
        weeklyUsedPercent: 100,
        weeklyResetAt: Date.now.addingTimeInterval(114344),
        weeklyResetAfterSeconds: 114344,
        hourlyUsedPercent: 0,
        hourlyResetAt: Date.now.addingTimeInterval(755),
        hourlyResetAfterSeconds: 755,
        hourlyWindowSeconds: 18000,
        limitReached: true, allowed: false, planType: "plus",
        creditBalance: nil,
        bonusCreditsSpentThisMonth: nil,
        approxLocalMessages: nil, approxCloudMessages: nil,
        fetchedAt: .now
    )

    public init(
        weeklyUsedPercent: Int, weeklyResetAt: Date, weeklyResetAfterSeconds: Int,
        hourlyUsedPercent: Int, hourlyResetAt: Date, hourlyResetAfterSeconds: Int,
        hourlyWindowSeconds: Int, limitReached: Bool, allowed: Bool, planType: String,
        creditBalance: Double?, bonusCreditsSpentThisMonth: Double? = nil,
        approxLocalMessages: [Int]?, approxCloudMessages: [Int]?,
        fetchedAt: Date
    ) {
        self.weeklyUsedPercent = weeklyUsedPercent
        self.weeklyResetAt = weeklyResetAt
        self.weeklyResetAfterSeconds = weeklyResetAfterSeconds
        self.hourlyUsedPercent = hourlyUsedPercent
        self.hourlyResetAt = hourlyResetAt
        self.hourlyResetAfterSeconds = hourlyResetAfterSeconds
        self.hourlyWindowSeconds = hourlyWindowSeconds
        self.limitReached = limitReached
        self.allowed = allowed
        self.planType = planType
        self.creditBalance = creditBalance
        self.bonusCreditsSpentThisMonth = bonusCreditsSpentThisMonth
        self.approxLocalMessages = approxLocalMessages
        self.approxCloudMessages = approxCloudMessages
        self.fetchedAt = fetchedAt
    }

    public func withBonusCreditsSpentThisMonth(_ spent: Double?) -> CodexUsage {
        CodexUsage(
            weeklyUsedPercent: weeklyUsedPercent,
            weeklyResetAt: weeklyResetAt,
            weeklyResetAfterSeconds: weeklyResetAfterSeconds,
            hourlyUsedPercent: hourlyUsedPercent,
            hourlyResetAt: hourlyResetAt,
            hourlyResetAfterSeconds: hourlyResetAfterSeconds,
            hourlyWindowSeconds: hourlyWindowSeconds,
            limitReached: limitReached,
            allowed: allowed,
            planType: planType,
            creditBalance: creditBalance,
            bonusCreditsSpentThisMonth: spent,
            approxLocalMessages: approxLocalMessages,
            approxCloudMessages: approxCloudMessages,
            fetchedAt: fetchedAt
        )
    }
}

public struct CodexCreditUsageEventsResponse: Decodable, Sendable, Equatable {
    public let data: [Event]

    public struct Event: Decodable, Sendable, Equatable {
        public let date: String
        public let productSurface: String?
        public let creditAmount: Double
    }

    public func monthToDateTotal(asOf date: Date = .now, calendar: Calendar = .current) -> Double {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else {
            return data.reduce(0) { $0 + $1.creditAmount }
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        return data.reduce(0) { total, event in
            guard let eventDate = formatter.date(from: event.date),
                  monthInterval.contains(eventDate)
            else { return total }
            return total + event.creditAmount
        }
    }
}

// MARK: - Auto-reload settings

/// Codex auto-reload state fetched from `/backend-api/subscriptions/auto_top_up/settings`.
/// When `isEnabled` is true, the balance refills automatically when it drops below
/// `rechargeThreshold` — hitting zero is routine, not a crisis.
public struct CodexAutoReload: Codable, Sendable, Equatable {
    public let isEnabled: Bool
    /// Balance level that triggers a refill (parsed from the JSON String field).
    public let rechargeThreshold: Double
    /// Balance target after a refill (parsed from the JSON String field).
    public let rechargeTarget: Double

    public init(isEnabled: Bool, rechargeThreshold: Double, rechargeTarget: Double) {
        self.isEnabled = isEnabled
        self.rechargeThreshold = rechargeThreshold
        self.rechargeTarget = rechargeTarget
    }
}

// Internal decode type — the API returns `rechargeThreshold` and `rechargeTarget` as
// JSON strings rather than numbers, so we can't decode directly into Double.
struct AutoTopUpSettingsResponse: Decodable, Sendable {
    let isEnabled: Bool
    let rechargeThreshold: String
    let rechargeTarget: String
}

private extension KeyedDecodingContainer {
    func decodeLossyIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value.rounded())
        }
        if let value = try? decodeIfPresent(String.self, forKey: key),
           let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Int(number.rounded())
        }
        return nil
    }

    func decodeLossyStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}
