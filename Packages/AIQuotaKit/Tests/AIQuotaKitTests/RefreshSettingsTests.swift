import Foundation
import Testing
@testable import AIQuotaKit

@Suite("Refresh settings")
struct RefreshSettingsTests {
    @Test("refresh defaults to Auto")
    func defaultsToAuto() {
        #expect(AppSettings.default.refreshIntervalMinutes == AppSettings.autoRefreshIntervalMinutes)
        #expect(AppSettings.default.usesAdaptiveRefresh)
        #expect(AppSettings.default.menuBarDisplayMode == .single)
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
        #expect(settings.menuBarDisplayMode == .single)
    }

    @Test("supported fixed refresh values still round-trip")
    func fixedValuesRoundTrip() throws {
        let encoded = try JSONEncoder().encode(
            AppSettings(
                refreshIntervalMinutes: 10,
                notifications: NotificationPreferences(),
                menuBarService: .claude,
                menuBarDisplayMode: .both,
                analyticsEnabled: false
            )
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        #expect(decoded.refreshIntervalMinutes == 10)
        #expect(decoded.fixedRefreshInterval == 600)
        #expect(decoded.menuBarService == .claude)
        #expect(decoded.menuBarDisplayMode == .both)
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

        #expect(settingsSource.contains("Auto refreshes every 5 min, speeds up to 1 min when usage is changing or near a threshold, and slows down when your Mac is idle."))
        #expect(settingsSource.contains("LabeledContent(\"Menu bar display\")"))
        #expect(servicesSource.contains("How often should AIQuota refresh?"))
        #expect(servicesSource.contains("What should show in your menu bar?"))
        #expect(servicesSource.contains("Auto refreshes every 5 min, speeds up to 1 min when usage is changing or near a threshold, and slows down when your Mac is idle."))
    }
}
