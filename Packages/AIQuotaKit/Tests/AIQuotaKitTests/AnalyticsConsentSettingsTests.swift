import Foundation
import Testing
@testable import AIQuotaKit

@Suite("Analytics consent settings")
struct AnalyticsConsentSettingsTests {
    @Test("analytics consent defaults to disabled")
    func defaultConsentIsDisabled() {
        #expect(AppSettings.default.analyticsEnabled == false)
    }

    @Test("missing analytics consent key decodes to disabled for older installs")
    func missingConsentKeyFallsBackToDisabled() throws {
        let legacyJSON = """
        {
          "refreshIntervalMinutes": 15,
          "menuBarService": "codex",
          "notifications": {
            "enabled": true
          }
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)

        #expect(settings.analyticsEnabled == false)
    }

    @Test("analytics consent round-trips when enabled")
    func consentRoundTrips() throws {
        let encoded = try JSONEncoder().encode(
            AppSettings(
                refreshIntervalMinutes: 30,
                notifications: NotificationPreferences(),
                menuBarService: .claude,
                menuBarDisplayMode: .both,
                analyticsEnabled: true
            )
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        #expect(decoded.analyticsEnabled == true)
        #expect(decoded.menuBarService == .claude)
        #expect(decoded.menuBarDisplayMode == .both)
        #expect(decoded.refreshIntervalMinutes == 30)
    }

    @Test("onboarding and settings expose the analytics consent copy")
    func sourceContainsConsentWiring() throws {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let onboardingSource = try String(
            contentsOf: repoRoot.appending(path: "AIQuota/Views/Onboarding/OnboardingView.swift"),
            encoding: .utf8
        )
        let doneSource = try String(
            contentsOf: repoRoot.appending(path: "AIQuota/Views/Onboarding/Steps/DoneStepView.swift"),
            encoding: .utf8
        )
        let analyticsCardSource = try String(
            contentsOf: repoRoot.appending(path: "AIQuota/Views/Onboarding/Steps/AnalyticsConsentStepView.swift"),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: repoRoot.appending(path: "AIQuota/Views/SettingsView.swift"),
            encoding: .utf8
        )

        #expect(!onboardingSource.contains("case analytics"))
        #expect(!onboardingSource.contains("AnalyticsConsentStepView()"))
        #expect(doneSource.contains("Text(\"You’re all set!\")"))
        #expect(doneSource.contains("AnalyticsConsentCard(isEnabled: $vm.settings.analyticsEnabled)"))
        #expect(analyticsCardSource.contains("Text(\"Share anonymous usage data\")"))
        #expect(analyticsCardSource.contains("Off by default"))
        #expect(analyticsCardSource.contains("Change anytime in Settings"))
        #expect(!analyticsCardSource.contains("LaunchAtLoginToggle()"))
        #expect(!analyticsCardSource.contains("Help John improve AIQuota"))
        #expect(settingsSource.contains("Share anonymous usage data"))
        #expect(settingsSource.contains("menubar_display_changed"))
    }
}
