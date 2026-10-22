import Foundation
import Testing
@testable import AIQuotaKit

@Suite("Refresh settings")
struct RefreshSettingsTests {
    @Test("refresh defaults to Auto")
    func defaultsToAuto() {
        #expect(AppSettings.default.refreshIntervalMinutes == AppSettings.autoRefreshIntervalMinutes)
        #expect(AppSettings.default.usesAdaptiveRefresh)
        #expect(AppSettings.default.menuBarDisplayMode == .both)
        #expect(
            MenuBarDisplayOption.current(
                settings: AppSettings.default,
                enrolledServices: [.codex]
            ) == .codex
        )
        #expect(
            MenuBarDisplayOption.current(
                settings: AppSettings.default,
                enrolledServices: [.codex, .claude]
            ) == .both
        )
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
        #expect(settings.menuBarDisplayMode == .both)
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

    @Test("onboarding explains Auto refresh")
    func sourceContainsRefreshCopy() throws {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let servicesSource = try String(
            contentsOf: repoRoot.appending(path: "AIQuota/Views/Onboarding/Steps/ServicesStepView.swift"),
            encoding: .utf8
        )

        #expect(servicesSource.contains("Refresh usage"))
        #expect(servicesSource.contains("Checks every 5 minutes, more often near a limit, and less often when your Mac is idle."))
    }
}
