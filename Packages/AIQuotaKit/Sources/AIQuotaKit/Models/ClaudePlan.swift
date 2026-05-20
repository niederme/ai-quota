import Foundation

/// Claude plan inference for OAuth and web usage responses.
///
/// Shape and compatibility heuristics are adapted from CodexBar's MIT-licensed
/// ClaudePlan resolver:
/// https://github.com/steipete/CodexBar
public enum ClaudePlan: String, CaseIterable, Sendable {
    case max
    case pro
    case team
    case enterprise
    case ultra

    public var label: ClaudeUsage.PlanLabel {
        switch self {
        case .max: .max
        case .pro: .pro
        case .team: .team
        case .enterprise: .enterprise
        case .ultra: .ultra
        }
    }

    public var countsAsSubscription: Bool {
        switch self {
        case .max, .pro, .team, .ultra:
            true
        case .enterprise:
            false
        }
    }

    public static func fromOAuthCredentials(subscriptionType: String?, rateLimitTier: String?) -> Self? {
        fromCompatibilityLabel(subscriptionType) ?? fromRateLimitTier(rateLimitTier)
    }

    public static func fromWebAccount(rateLimitTier: String?, billingType: String?) -> Self? {
        if let plan = fromRateLimitTier(rateLimitTier) {
            return plan
        }

        let tier = normalized(rateLimitTier)
        let billing = normalized(billingType)
        if billing.contains("stripe"), tier.contains("claude") {
            return .pro
        }
        return nil
    }

    public static func fromCompatibilityLabel(_ label: String?) -> Self? {
        let words = normalizedWords(label)
        if words.contains("max") { return .max }
        if words.contains("pro") { return .pro }
        if words.contains("team") { return .team }
        if words.contains("enterprise") { return .enterprise }
        if words.contains("ultra") { return .ultra }
        return nil
    }

    public static func label(subscriptionType: String?, rateLimitTier: String?) -> ClaudeUsage.PlanLabel? {
        fromOAuthCredentials(subscriptionType: subscriptionType, rateLimitTier: rateLimitTier)?.label
    }

    private static func fromRateLimitTier(_ rateLimitTier: String?) -> Self? {
        let tier = normalized(rateLimitTier)
        if tier.contains("max") { return .max }
        if tier.contains("pro") { return .pro }
        if tier.contains("team") { return .team }
        if tier.contains("enterprise") { return .enterprise }
        if tier.contains("ultra") { return .ultra }
        return nil
    }

    private static func normalized(_ text: String?) -> String {
        text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func normalizedWords(_ text: String?) -> [String] {
        normalized(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
