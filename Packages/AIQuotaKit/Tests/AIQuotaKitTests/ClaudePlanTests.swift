import Testing
@testable import AIQuotaKit

@Suite("Claude plan resolver")
struct ClaudePlanTests {
    @Test("OAuth rate limit tier maps to Claude plan label")
    func oauthRateLimitTierMapsToPlanLabel() {
        #expect(ClaudePlan.label(subscriptionType: nil, rateLimitTier: "default_claude_max_20x") == .max)
        #expect(ClaudePlan.label(subscriptionType: nil, rateLimitTier: "claude_pro") == .pro)
        #expect(ClaudePlan.label(subscriptionType: nil, rateLimitTier: "claude_team") == .team)
        #expect(ClaudePlan.label(subscriptionType: nil, rateLimitTier: "claude_enterprise") == .enterprise)
        #expect(ClaudePlan.label(subscriptionType: nil, rateLimitTier: "claude_ultra") == .ultra)
    }

    @Test("OAuth subscription type wins over generic rate limit tier")
    func subscriptionTypeWinsOverRateLimitTier() {
        #expect(ClaudePlan.label(subscriptionType: "pro", rateLimitTier: "default_claude_ai") == .pro)
        #expect(ClaudePlan.label(subscriptionType: "team", rateLimitTier: "default_claude_max_5x") == .team)
        #expect(ClaudePlan.label(subscriptionType: nil, rateLimitTier: "default_claude_ai") == nil)
    }

    @Test("Enterprise is not counted as a consumer subscription")
    func subscriptionCounting() {
        #expect(ClaudePlan.max.countsAsSubscription)
        #expect(ClaudePlan.pro.countsAsSubscription)
        #expect(ClaudePlan.team.countsAsSubscription)
        #expect(ClaudePlan.ultra.countsAsSubscription)
        #expect(!ClaudePlan.enterprise.countsAsSubscription)
    }
}
