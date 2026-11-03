import Foundation

/// Optional account-scoped WHAM metadata. Unknown is distinct from confirmed zero.
/// Available is a banked balance, not a promise of immediate redemption eligibility.
public struct CodexResetCredits: Codable, Equatable, Sendable {
    public let availableCount: Int?
    public let applicableAvailableCount: Int?

    public init(availableCount: Int?, applicableAvailableCount: Int? = nil) {
        let available = availableCount.flatMap { $0 >= 0 ? $0 : nil }
        let applicable = applicableAvailableCount.flatMap { $0 >= 0 ? $0 : nil }
        if let available, let applicable, applicable > available {
            self.availableCount = nil
            self.applicableAvailableCount = nil
        } else {
            self.availableCount = available
            self.applicableAvailableCount = applicable
        }
    }

    // Accept raw WHAM and the Mac decoder's convertFromSnakeCase strategy,
    // plus the camel-case form used in app caches. Malformed optional metadata
    // must neither invent a balance nor fail the successful quota reading.
    private enum CodingKeys: String, CodingKey {
        case availableCount, applicableAvailableCount
        case availableSnake = "available_count", applicableSnake = "applicable_available_count"
    }
    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init(availableCount: nil)
            return
        }
        self.init(availableCount: (try? c.decode(Int.self, forKey: .availableCount)) ?? (try? c.decode(Int.self, forKey: .availableSnake)),
                  applicableAvailableCount: (try? c.decode(Int.self, forKey: .applicableAvailableCount)) ?? (try? c.decode(Int.self, forKey: .applicableSnake)))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(availableCount, forKey: .availableCount)
        try c.encodeIfPresent(applicableAvailableCount, forKey: .applicableAvailableCount)
    }
}

/// Ephemeral UI context tied to exactly the account/identity that supplied it.
/// Never derives entitlement from public reset announcements or another account.
public struct CodexBankedResetContext: Equatable, Sendable {
    public static let maximumAge: TimeInterval = 5 * 60
    public let accountID: String
    public let providerIdentity: String
    public let credits: CodexResetCredits
    public let fetchedAt: Date

    public init(accountID: String, providerIdentity: String, credits: CodexResetCredits, fetchedAt: Date) {
        self.accountID = accountID; self.providerIdentity = providerIdentity
        self.credits = credits; self.fetchedAt = fetchedAt
    }
    public func availableCount(for forecast: QuotaExhaustionForecast, now: Date) -> Int? {
        guard forecast.scope.provider == "codex", forecast.scope.window == .weekly,
              !accountID.isEmpty, !providerIdentity.isEmpty,
              forecast.scope.accountID == accountID, forecast.scope.identity == providerIdentity,
              now.timeIntervalSince1970.isFinite, fetchedAt.timeIntervalSince1970.isFinite,
              fetchedAt <= now, now.timeIntervalSince(fetchedAt) <= Self.maximumAge,
              forecast.scope.resetAt > now, forecast.validUntil > now else { return nil }
        return credits.availableCount
    }
}
