import Foundation
import Testing
@testable import MobileAccessCore

private func reading(fetchedAt: Date) -> QuotaReading {
    QuotaReading(fetchedAt: fetchedAt, shortTerm: nil, weekly: nil)
}

@Test func recentReadingSuppressesAutomaticRefreshForThirtySeconds() {
    let fetchedAt = Date(timeIntervalSince1970: 10_000)
    var policy = ForegroundRefreshPolicy()

    let at29Seconds = policy.beginAutomatic(
        at: fetchedAt.addingTimeInterval(29), reading: reading(fetchedAt: fetchedAt)
    )
    let at30Seconds = policy.beginAutomatic(
        at: fetchedAt.addingTimeInterval(30), reading: reading(fetchedAt: fetchedAt)
    )
    #expect(!at29Seconds)
    #expect(at30Seconds)
}

@Test func futureReadingDoesNotCountAsSuccessfulRefresh() {
    let now = Date(timeIntervalSince1970: 10_000)
    var policy = ForegroundRefreshPolicy()

    let allowed = policy.beginAutomatic(at: now, reading: reading(fetchedAt: now.addingTimeInterval(1)))
    #expect(allowed)
}

@Test func crossedResetMakesEvenARecentlyFetchedReadingEligible() throws {
    let fetchedAt = Date(timeIntervalSince1970: 10_000)
    let resetAt = fetchedAt.addingTimeInterval(10)
    let value = try QuotaReading.decode(
        Data(#"{"rate_limit":{"primary_window":{"used_percent":100,"limit_window_seconds":18000,"reset_at":10010}}}"#.utf8),
        now: fetchedAt
    )
    var policy = ForegroundRefreshPolicy()

    #expect(!WidgetFreshness.isOld(value, at: resetAt.addingTimeInterval(-1)))
    #expect(WidgetFreshness.isOld(value, at: resetAt))
    let allowed = policy.beginAutomatic(at: resetAt, reading: value)
    #expect(allowed)
}

@Test func failedAutomaticAttemptsUseOnlyTheRetryThrottle() {
    let fetchedAt = Date(timeIntervalSince1970: 10_000)
    let staleReading = reading(fetchedAt: fetchedAt)
    var policy = ForegroundRefreshPolicy()

    let first = policy.beginAutomatic(at: fetchedAt.addingTimeInterval(30), reading: staleReading)
    let throttled = policy.beginAutomatic(at: fetchedAt.addingTimeInterval(44), reading: staleReading)
    let retried = policy.beginAutomatic(at: fetchedAt.addingTimeInterval(45), reading: staleReading)
    #expect(first)
    #expect(!throttled)
    #expect(retried)
}

@Test func suppressedAttemptsDoNotExtendTheRetryThrottle() {
    let now = Date(timeIntervalSince1970: 10_000)
    var policy = ForegroundRefreshPolicy()

    let first = policy.beginAutomatic(at: now, reading: nil)
    let throttled = policy.beginAutomatic(at: now.addingTimeInterval(14), reading: nil)
    let retried = policy.beginAutomatic(at: now.addingTimeInterval(15), reading: nil)
    #expect(first)
    #expect(!throttled)
    #expect(retried)
}

@Test func resetClearsTheAccountRetryState() {
    let now = Date(timeIntervalSince1970: 10_000)
    var policy = ForegroundRefreshPolicy()

    let first = policy.beginAutomatic(at: now, reading: nil)
    policy.reset()
    let afterReset = policy.beginAutomatic(at: now.addingTimeInterval(1), reading: nil)
    #expect(first)
    #expect(afterReset)
}

@Test func policyInstancesThrottleIndependently() {
    let now = Date(timeIntervalSince1970: 10_000)
    var codex = ForegroundRefreshPolicy()
    var claude = ForegroundRefreshPolicy()

    let codexFirst = codex.beginAutomatic(at: now, reading: nil)
    let codexSecond = codex.beginAutomatic(at: now.addingTimeInterval(1), reading: nil)
    let claudeFirst = claude.beginAutomatic(at: now.addingTimeInterval(1), reading: nil)
    #expect(codexFirst)
    #expect(!codexSecond)
    #expect(claudeFirst)
}

@Test func newerWidgetReadingSuppressesASecondFetch() {
    let now = Date(timeIntervalSince1970: 10_000)
    var policy = ForegroundRefreshPolicy()

    let initial = policy.beginAutomatic(at: now, reading: reading(fetchedAt: now.addingTimeInterval(-60)))
    let widgetReading = reading(fetchedAt: now.addingTimeInterval(2))
    let suppressed = policy.beginAutomatic(at: now.addingTimeInterval(20), reading: widgetReading)
    let afterFreshnessWindow = policy.beginAutomatic(at: now.addingTimeInterval(32), reading: widgetReading)
    #expect(initial)
    #expect(!suppressed)
    #expect(afterFreshnessWindow)
}

@Test func manualAndTimerReadingsUpdateSuccessfulFreshness() {
    let now = Date(timeIntervalSince1970: 10_000)
    let oldReading = reading(fetchedAt: now.addingTimeInterval(-60))
    var manualPolicy = ForegroundRefreshPolicy()
    var timerPolicy = ForegroundRefreshPolicy()

    let manualInitial = manualPolicy.beginAutomatic(at: now, reading: oldReading)
    let timerInitial = timerPolicy.beginAutomatic(at: now, reading: oldReading)

    let manualReading = reading(fetchedAt: now.addingTimeInterval(1))
    let timerReading = reading(fetchedAt: now.addingTimeInterval(2))
    let manualSuppressed = manualPolicy.beginAutomatic(at: now.addingTimeInterval(20), reading: manualReading)
    let timerSuppressed = timerPolicy.beginAutomatic(at: now.addingTimeInterval(20), reading: timerReading)
    let manualExpired = manualPolicy.beginAutomatic(at: now.addingTimeInterval(31), reading: manualReading)
    let timerExpired = timerPolicy.beginAutomatic(at: now.addingTimeInterval(32), reading: timerReading)
    #expect(manualInitial)
    #expect(timerInitial)
    #expect(!manualSuppressed)
    #expect(!timerSuppressed)
    #expect(manualExpired)
    #expect(timerExpired)
}
