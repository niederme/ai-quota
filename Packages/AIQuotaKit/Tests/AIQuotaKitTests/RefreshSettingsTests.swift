import Foundation
import Testing
@testable import AIQuotaKit

@Suite("Refresh settings")
struct RefreshSettingsTests {
    @Test("refresh defaults to Auto")
    func defaultsToAuto() {
        #expect(AppSettings.default.refreshIntervalMinutes == AppSettings.autoRefreshIntervalMinutes)
        #expect(AppSettings.default.usesAdaptiveRefresh)
    }

    @Test("legacy fixed refresh values normalize into the new supported set")
    func legacyValuesNormalizeToAuto() throws {
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

        #expect(settings.refreshIntervalMinutes == AppSettings.autoRefreshIntervalMinutes)
        #expect(settings.usesAdaptiveRefresh)
    }

    @Test("supported fixed refresh values still round-trip")
    func fixedValuesRoundTrip() throws {
        let encoded = try JSONEncoder().encode(
            AppSettings(
                refreshIntervalMinutes: 10,
                notifications: NotificationPreferences(),
                menuBarService: .claude,
                analyticsEnabled: false
            )
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        #expect(decoded.refreshIntervalMinutes == 10)
        #expect(decoded.fixedRefreshInterval == 600)
    }

    @Test("settings and onboarding both expose the Auto refresh copy")
    func sourceContainsRefreshCopy() throws {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let settingsSource = try String(
            contentsOf: repoRoot.appending(path: "AIQuota/Views/SettingsView.swift"),
            encoding: .utf8
        )
        let servicesSource = try String(
            contentsOf: repoRoot.appending(path: "AIQuota/Views/Onboarding/Steps/ServicesStepView.swift"),
            encoding: .utf8
        )

        #expect(settingsSource.contains("Auto refreshes faster when the app is active and slows down when idle."))
        #expect(servicesSource.contains("How often should AIQuota refresh?"))
        #expect(servicesSource.contains("Auto refreshes faster when the app is active and slows down when idle."))
    }
}
