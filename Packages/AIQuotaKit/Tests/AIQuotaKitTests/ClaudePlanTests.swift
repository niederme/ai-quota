import Foundation
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

    @Test("Web organization list reports the plan of the requested organization only")
    func webOrganizationsReportRequestedPlan() {
        let data = Data("""
        [
          {"uuid": "11111111-1111-1111-1111-111111111111", "capabilities": ["chat", "raven"], "rate_limit_tier": "default_raven", "billing_type": "usage_based"},
          {"uuid": "22222222-2222-2222-2222-222222222222", "capabilities": ["chat", "claude_max"], "rate_limit_tier": "default_claude_max_20x", "billing_type": "stripe_subscription"},
          {"uuid": "33333333-3333-3333-3333-333333333333", "capabilities": ["chat"], "rate_limit_tier": "default_claude_ai", "billing_type": "stripe_subscription"},
          {"uuid": "44444444-4444-4444-4444-444444444444", "capabilities": ["api"]}
        ]
        """.utf8)
        #expect(ClaudePlan.fromWebOrganizations(data, organizationID: "22222222-2222-2222-2222-222222222222") == .max)
        #expect(ClaudePlan.fromWebOrganizations(data, organizationID: "22222222-2222-2222-2222-222222222222".uppercased()) == .max)
        #expect(ClaudePlan.fromWebOrganizations(data, organizationID: "33333333-3333-3333-3333-333333333333") == .pro)
        // Nothing names a plan: unreported, never guessed.
        #expect(ClaudePlan.fromWebOrganizations(data, organizationID: "11111111-1111-1111-1111-111111111111") == nil)
        #expect(ClaudePlan.fromWebOrganizations(data, organizationID: "44444444-4444-4444-4444-444444444444") == nil)
        #expect(ClaudePlan.fromWebOrganizations(data, organizationID: "55555555-5555-5555-5555-555555555555") == nil)
        #expect(ClaudePlan.fromWebOrganizations(Data("not json".utf8), organizationID: "22222222-2222-2222-2222-222222222222") == nil)
    }

    @Test("Account memberships report the plan of the requested organization only")
    func webAccountReportsRequestedMembershipPlan() {
        let data = Data("""
        {
          "email_address": "someone@example.com",
          "memberships": [
            {"seat_tier": null, "organization": {"uuid": "11111111-1111-1111-1111-111111111111", "name": "Work", "rate_limit_tier": "claude_enterprise", "billing_type": "usage_based"}},
            {"organization": {"uuid": "22222222-2222-2222-2222-222222222222", "name": "Personal", "rate_limit_tier": "default_claude_max_20x", "billing_type": "stripe_subscription"}},
            {"organization": {"uuid": "33333333-3333-3333-3333-333333333333", "name": "Other", "rate_limit_tier": null}}
          ]
        }
        """.utf8)
        #expect(ClaudePlan.fromWebAccountResponse(data, organizationID: "22222222-2222-2222-2222-222222222222") == .max)
        #expect(ClaudePlan.fromWebAccountResponse(data, organizationID: "11111111-1111-1111-1111-111111111111") == .enterprise)
        // Unreported or unknown organization: no plan, and never a sibling's plan.
        #expect(ClaudePlan.fromWebAccountResponse(data, organizationID: "33333333-3333-3333-3333-333333333333") == nil)
        #expect(ClaudePlan.fromWebAccountResponse(data, organizationID: "44444444-4444-4444-4444-444444444444") == nil)
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
