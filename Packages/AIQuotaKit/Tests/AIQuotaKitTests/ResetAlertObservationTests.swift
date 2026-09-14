import Foundation
import Testing
@testable import AIQuotaKit

@Test func resetRequiresNewWindowAndUsesPriorPeakOnce() throws {
    let now = Date(timeIntervalSince1970: 1800000000)
    var observation = ResetAlertObservation(end: now, peak: 18)
    #expect(observation.observe(used: 98, end: now, now: now.addingTimeInterval(-1)) == nil)
    #expect(observation.observe(used: 0, end: now, now: now.addingTimeInterval(1)) == nil)
    let saved = try JSONEncoder().encode(observation)
    observation = try JSONDecoder().decode(ResetAlertObservation.self, from: saved)
    let peak = observation.observe(used: 2, end: now.addingTimeInterval(18000), now: now.addingTimeInterval(1))
    #expect(peak == 98)
    #expect(ResetAlertObservation.allows(priorPeak: peak, minimum: 90))
    #expect(observation.observe(used: 3, end: now.addingTimeInterval(18000), now: now.addingTimeInterval(2)) == nil)
    #expect(!ResetAlertObservation.allows(priorPeak: 18, minimum: 90))
    #expect(ResetAlertObservation.allows(priorPeak: 18, minimum: 0))
    #expect(!ResetAlertObservation.allows(priorPeak: nil, minimum: 0))
}
@Test func legacyPreferencesKeepOffAndDefaultNearLimit() throws {
    let prefs = try JSONDecoder().decode(NotificationPreferences.self, from: Data(#"{"codex5hReset":false}"#.utf8))
    #expect(!prefs.codex5hReset)
    #expect(prefs.codex5hResetMinimum == 90)
    #expect(prefs.claude7dResetMinimum == 90)
    #expect(try JSONDecoder().decode(NotificationPreferences.self, from: JSONEncoder().encode(prefs)) == prefs)
}
