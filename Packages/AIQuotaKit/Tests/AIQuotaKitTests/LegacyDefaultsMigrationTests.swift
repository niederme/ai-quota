import Foundation
import Testing
@testable import AIQuotaKit

@Suite("LegacyDefaultsMigration", .serialized)
struct LegacyDefaultsMigrationTests {
    @Test("migrates app-owned keys from legacy plist into current defaults")
    func migratesKeys() throws {
        let suiteName = "LegacyDefaultsMigrationTests.\(UUID().uuidString)"
        guard let current = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        current.removePersistentDomain(forName: suiteName)

        let legacyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString).plist")
        let legacy: NSDictionary = [
            "app.installedAt.v2": true,
            "onboarding.v1.hasCompleted": true,
            "codex.signedOutByUser": true,
        ]
        legacy.write(to: legacyURL, atomically: true)
        defer {
            current.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: legacyURL)
        }

        LegacyDefaultsMigration.migrateIfNeeded(
            bundleIdentifier: "com.niederme.AIQuota",
            currentDefaults: current,
            legacyPlistURL: legacyURL
        )

        #expect(current.bool(forKey: "app.installedAt.v2"))
        #expect(current.bool(forKey: "onboarding.v1.hasCompleted"))
        #expect(current.bool(forKey: "codex.signedOutByUser"))
        #expect(current.bool(forKey: "defaults.legacyPrefsMigrated.v1"))
    }

    @Test("does not overwrite current defaults with legacy values")
    func preservesCurrentValues() throws {
        let suiteName = "LegacyDefaultsMigrationTests.\(UUID().uuidString)"
        guard let current = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        current.removePersistentDomain(forName: suiteName)
        current.set(false, forKey: "onboarding.v1.hasCompleted")

        let legacyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString).plist")
        let legacy: NSDictionary = [
            "onboarding.v1.hasCompleted": true,
        ]
        legacy.write(to: legacyURL, atomically: true)
        defer {
            current.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: legacyURL)
        }

        LegacyDefaultsMigration.migrateIfNeeded(
            bundleIdentifier: "com.niederme.AIQuota",
            currentDefaults: current,
            legacyPlistURL: legacyURL
        )

        #expect(current.bool(forKey: "onboarding.v1.hasCompleted") == false)
    }
}
