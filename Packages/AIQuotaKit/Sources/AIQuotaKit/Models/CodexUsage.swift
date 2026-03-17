import Foundation

// MARK: - Raw API response from GET https://chatgpt.com/backend-api/wham/usage

public struct WhamUsageResponse: Decodable, Sendable {
    public let userId: String
    public let accountId: String
    public let email: String?
    public let planType: String
    public let rateLimit: RateLimitInfo
    public let codeReviewRateLimit: RateLimitInfo?
    public let credits: Credits?

    public struct RateLimitInfo: Decodable, Sendable {
        public let allowed: Bool
        public let limitReached: Bool
        public let primaryWindow: Window?   // short window (~5h)
        public let secondaryWindow: Window? // weekly window (7 days)

        public struct Window: Decodable, Sendable {
            public let usedPercent: Int
            public let limitWindowSeconds: Int
            public let resetAfterSeconds: Int
            public let resetAt: Int // Unix timestamp
        }
    }

    public struct Credits: Decodable, Sendable {
        public let hasCredits: Bool
        public let unlimited: Bool
        public let balance: String
        // [current, limit] — e.g. [49, 256] means 49 of 256 used
        public let approxLocalMessages: [Int]?
        public let approxCloudMessages: [Int]?
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
    public let approxLocalMessages: [Int]?  // [used, limit]
    public let approxCloudMessages: [Int]?  // [used, limit]

    public let fetchedAt: Date

    // MARK: Computed

    public var weeklyPercentFraction: Double { Double(weeklyUsedPercent) / 100.0 }
    public var hourlyPercentFraction: Double { Double(hourlyUsedPercent) / 100.0 }
    public var weeklyRemaining: Int { max(0, 100 - weeklyUsedPercent) }
    public var isWeeklyExhausted: Bool { weeklyUsedPercent >= 100 }

    public var localMessagesUsed: Int? { approxLocalMessages?.first }
    public var localMessagesLimit: Int? { approxLocalMessages?.last }
    public var cloudMessagesUsed: Int? { approxCloudMessages?.first }
    public var cloudMessagesLimit: Int? { approxCloudMessages?.last }

    // MARK: Init from API response

    public init(from response: WhamUsageResponse, fetchedAt: Date = .now) {
        let weekly = response.rateLimit.secondaryWindow
        let hourly = response.rateLimit.primaryWindow

        weeklyUsedPercent = weekly?.usedPercent ?? 0
        weeklyResetAt = weekly.map { Date(timeIntervalSince1970: TimeInterval($0.resetAt)) } ?? .distantFuture
        weeklyResetAfterSeconds = weekly?.resetAfterSeconds ?? 0

        hourlyUsedPercent = hourly?.usedPercent ?? 0
        hourlyResetAt = hourly.map { Date(timeIntervalSince1970: TimeInterval($0.resetAt)) } ?? .distantFuture
        hourlyResetAfterSeconds = hourly?.resetAfterSeconds ?? 0
        hourlyWindowSeconds = hourly?.limitWindowSeconds ?? 18000

        limitReached = response.rateLimit.limitReached
        allowed = response.rateLimit.allowed
        planType = response.planType

        creditBalance = response.credits.flatMap { Double($0.balance) }
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
        approxLocalMessages: nil, approxCloudMessages: nil,
        fetchedAt: .now
    )

    private init(
        weeklyUsedPercent: Int, weeklyResetAt: Date, weeklyResetAfterSeconds: Int,
        hourlyUsedPercent: Int, hourlyResetAt: Date, hourlyResetAfterSeconds: Int,
        hourlyWindowSeconds: Int, limitReached: Bool, allowed: Bool, planType: String,
        creditBalance: Double?, approxLocalMessages: [Int]?, approxCloudMessages: [Int]?,
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
        self.approxLocalMessages = approxLocalMessages
        self.approxCloudMessages = approxCloudMessages
        self.fetchedAt = fetchedAt
    }
}
