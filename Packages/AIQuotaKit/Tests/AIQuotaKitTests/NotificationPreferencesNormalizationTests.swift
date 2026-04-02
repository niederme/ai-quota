import Testing
@testable import AIQuotaKit

@Suite("NotificationPreferences normalization")
struct NotificationPreferencesNormalizationTests {

    // MARK: - normalizeThresholds()

    @Test("all-on groups stay all-on")
    func allOnUnchanged() {
        var prefs = NotificationPreferences()
        // defaults are all true — should be a no-op
        prefs.normalizeThresholds()
        #expect(prefs.codex5hAt15 && prefs.codex5hAt5 && prefs.codex5hLimitReached)
        #expect(prefs.codexAt15 && prefs.codexAt5 && prefs.codexLimitReached)
        #expect(prefs.claude5hAt15 && prefs.claude5hAt5 && prefs.claude5hLimitReached)
        #expect(prefs.claude7dAt80 && prefs.claude7dAt95 && prefs.claude7dLimitReached)
    }

    @Test("all-off groups stay all-off")
    func allOffUnchanged() {
        var prefs = NotificationPreferences()
        prefs.codex5hAt15 = false; prefs.codex5hAt5 = false; prefs.codex5hLimitReached = false
        prefs.codexAt15 = false; prefs.codexAt5 = false; prefs.codexLimitReached = false
        prefs.claude5hAt15 = false; prefs.claude5hAt5 = false; prefs.claude5hLimitReached = false
        prefs.claude7dAt80 = false; prefs.claude7dAt95 = false; prefs.claude7dLimitReached = false
        prefs.normalizeThresholds()
        #expect(!prefs.codex5hAt15 && !prefs.codex5hAt5 && !prefs.codex5hLimitReached)
        #expect(!prefs.codexAt15 && !prefs.codexAt5 && !prefs.codexLimitReached)
        #expect(!prefs.claude5hAt15 && !prefs.claude5hAt5 && !prefs.claude5hLimitReached)
        #expect(!prefs.claude7dAt80 && !prefs.claude7dAt95 && !prefs.claude7dLimitReached)
    }

    @Test("mixed group where any=true normalises to all-true")
    func mixedPartialOnBecomesAllOn() {
        var prefs = NotificationPreferences()
        // Only one of three is on in the Codex 5h group
        prefs.codex5hAt15 = false
        prefs.codex5hAt5 = false
        prefs.codex5hLimitReached = true   // one left on
        prefs.normalizeThresholds()
        #expect(prefs.codex5hAt15)
        #expect(prefs.codex5hAt5)
        #expect(prefs.codex5hLimitReached)
    }

    @Test("mixed group where any=true normalises independently per group")
    func eachGroupNormalisedIndependently() {
        var prefs = NotificationPreferences()
        // Codex weekly: only limit reached is on — should become all-on
        prefs.codexAt15 = false; prefs.codexAt5 = false; prefs.codexLimitReached = true
        // Claude 7d: all off — should stay all-off
        prefs.claude7dAt80 = false; prefs.claude7dAt95 = false; prefs.claude7dLimitReached = false
        prefs.normalizeThresholds()
        #expect(prefs.codexAt15 && prefs.codexAt5 && prefs.codexLimitReached)
        #expect(!prefs.claude7dAt80 && !prefs.claude7dAt95 && !prefs.claude7dLimitReached)
    }

    // MARK: - Aggregate computed properties

    @Test("codex5hThresholdAlerts is true when all three are true")
    func aggregateAllOnIsTrue() {
        let prefs = NotificationPreferences()
        #expect(prefs.codex5hThresholdAlerts == true)
    }

    @Test("codex5hThresholdAlerts is false when all three are false")
    func aggregateAllOffIsFalse() {
        var prefs = NotificationPreferences()
        prefs.codex5hAt15 = false; prefs.codex5hAt5 = false; prefs.codex5hLimitReached = false
        #expect(prefs.codex5hThresholdAlerts == false)
    }

    @Test("setting codex5hThresholdAlerts=false clears all three fields")
    func aggregateSetFalseClearsAll() {
        var prefs = NotificationPreferences()
        prefs.codex5hThresholdAlerts = false
        #expect(!prefs.codex5hAt15 && !prefs.codex5hAt5 && !prefs.codex5hLimitReached)
    }

    @Test("setting codex5hThresholdAlerts=true sets all three fields")
    func aggregateSetTrueSetsAll() {
        var prefs = NotificationPreferences()
        prefs.codex5hAt15 = false; prefs.codex5hAt5 = false; prefs.codex5hLimitReached = false
        prefs.codex5hThresholdAlerts = true
        #expect(prefs.codex5hAt15 && prefs.codex5hAt5 && prefs.codex5hLimitReached)
    }

    @Test("codexWeeklyThresholdAlerts is true when all three are true")
    func codexWeeklyAggregateAllOnIsTrue() {
        let prefs = NotificationPreferences()
        #expect(prefs.codexWeeklyThresholdAlerts == true)
    }

    @Test("claude5hThresholdAlerts is true when all three are true")
    func claude5hAggregateAllOnIsTrue() {
        let prefs = NotificationPreferences()
        #expect(prefs.claude5hThresholdAlerts == true)
    }

    @Test("claude7dThresholdAlerts is false when all three are false")
    func claude7dAggregateAllOffIsFalse() {
        var prefs = NotificationPreferences()
        prefs.claude7dAt80 = false; prefs.claude7dAt95 = false; prefs.claude7dLimitReached = false
        #expect(prefs.claude7dThresholdAlerts == false)
    }

    @Test("setting claude7dThresholdAlerts=false clears all three fields")
    func claude7dAggregateSetFalseClearsAll() {
        var prefs = NotificationPreferences()
        prefs.claude7dThresholdAlerts = false
        #expect(!prefs.claude7dAt80 && !prefs.claude7dAt95 && !prefs.claude7dLimitReached)
    }
}
