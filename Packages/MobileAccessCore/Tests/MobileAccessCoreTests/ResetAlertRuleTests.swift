import Testing
@testable import MobileAccessCore

@Test func resetAlertDefaultsAndControls() {
    let rule = ResetAlertRule()
    #expect(!rule.allows(usedPercent: 18))
    #expect(!rule.allows(usedPercent: 89))
    #expect(rule.allows(usedPercent: 90))
    #expect(rule.allows(usedPercent: 100))
    #expect(!ResetAlertRule(mode: .off).allows(usedPercent: 100))
    #expect(ResetAlertRule(mode: .everyReset).allows(usedPercent: 18))
    #expect(ResetAlertRule(threshold: 75).allows(usedPercent: 75))
    #expect(!ResetAlertRule(threshold: .nan).allows(usedPercent: 18))
    #expect(!rule.allows(usedPercent: .nan))
}

import Foundation
@Test func usageAlertsDeduplicateAndResetWithNewWindow() throws {
    let now = Date.now
    var state = UsageAlertState(windowEnd: now.addingTimeInterval(3600))
    #expect(state.next(used: 18, now: now, enabled: true, threshold: 90) == nil)
    #expect(state.next(used: 90, now: now, enabled: true, threshold: 90) == 90)
    state.highestNotified = 90
    state = try JSONDecoder().decode(UsageAlertState.self, from: JSONEncoder().encode(state))
    #expect(state.next(used: 98, now: now, enabled: true, threshold: 90) == nil)
    #expect(state.next(used: 100, now: now, enabled: true, threshold: 90) == nil)
    state.highestNotified = 100
    #expect(state.next(used: 100, now: now, enabled: true, threshold: 90) == nil)
    #expect(state.next(used: 100, now: now.addingTimeInterval(3601), enabled: true, threshold: 90) == nil)
}

@Test func singleUsageThresholdBoundaries() throws {
    let now = Date.now
    var state = UsageAlertState(windowEnd: now.addingTimeInterval(3600))
    #expect(state.next(used: 89.9, now: now, enabled: true) == nil)
    #expect(state.next(used: 90, now: now, enabled: true) == 90)
    #expect(state.next(used: 100, now: now, enabled: false) == nil)
    #expect(state.next(used: 70, now: now, enabled: true, threshold: 70) == 70)
    #expect(state.next(used: .nan, now: now, enabled: true) == nil)
    state.highestNotified = 90
    state = try JSONDecoder().decode(UsageAlertState.self, from: JSONEncoder().encode(state))
    #expect(state.next(used: 100, now: now, enabled: true, threshold: 95) == nil)
    state = UsageAlertState(windowEnd: now.addingTimeInterval(7200))
    #expect(state.next(used: 90, now: now, enabled: true) == 90)
}

@Test func correctedResetTimeDoesNotRearmUsageAlert() {
    let now = Date.now
    var state = UsageAlertState(windowEnd: now.addingTimeInterval(3600), highestNotified: 90)
    state.updateWindow(end: now.addingTimeInterval(3660), now: now)
    #expect(state.next(used: 95, now: now, enabled: true) == nil)
    let nextWindow = now.addingTimeInterval(3700)
    state.updateWindow(end: now.addingTimeInterval(7200), now: nextWindow)
    #expect(state.next(used: 90, now: nextWindow, enabled: true) == 90)
}
