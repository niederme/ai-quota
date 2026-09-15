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
    #expect(state.next(used: 18, now: now, nearEnabled: true, nearThreshold: 85, limitEnabled: true) == nil)
    #expect(state.next(used: 90, now: now, nearEnabled: true, nearThreshold: 85, limitEnabled: true) == 85)
    state.highestNotified = 85
    state = try JSONDecoder().decode(UsageAlertState.self, from: JSONEncoder().encode(state))
    #expect(state.next(used: 98, now: now, nearEnabled: true, nearThreshold: 85, limitEnabled: true) == nil)
    #expect(state.next(used: 100, now: now, nearEnabled: true, nearThreshold: 85, limitEnabled: true) == 100)
    state.highestNotified = 100
    #expect(state.next(used: 100, now: now, nearEnabled: true, nearThreshold: 85, limitEnabled: true) == nil)
    #expect(state.next(used: 100, now: now.addingTimeInterval(3601), nearEnabled: true, nearThreshold: 85, limitEnabled: true) == nil)
}
