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
                analyticsEnabled: true
            )
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        #expect(decoded.analyticsEnabled == true)
        #expect(decoded.menuBarService == .claude)
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
        let analyticsStepSource = try String(
            contentsOf: repoRoot.appending(path: "AIQuota/Views/Onboarding/Steps/AnalyticsConsentStepView.swift"),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: repoRoot.appending(path: "AIQuota/Views/SettingsView.swift"),
            encoding: .utf8
        )

        #expect(onboardingSource.contains("case analytics"))
        #expect(onboardingSource.contains("AnalyticsConsentStepView()"))
        #expect(analyticsStepSource.contains("Text(\"Optional\")"))
        #expect(analyticsStepSource.contains("Text(\"Help John improve AIQuota\")"))
        #expect(analyticsStepSource.contains("AnalyticsTrustIllustration()"))
        #expect(analyticsStepSource.contains("Anonymous only"))
        #expect(analyticsStepSource.contains("Off by default"))
        #expect(analyticsStepSource.contains("Change anytime in Settings"))
        #expect(settingsSource.contains("Help John improve AIQuota with anonymous usage analytics"))
    }
}
