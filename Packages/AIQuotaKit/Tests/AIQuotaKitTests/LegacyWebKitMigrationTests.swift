import Foundation
import Testing
@testable import AIQuotaKit

@Suite("LegacyWebKitMigration", .serialized)
struct LegacyWebKitMigrationTests {
    @Test("copies legacy WebKit tree into container library")
    func copiesLegacyWebKitTree() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyWebKitMigrationTests-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let currentLibrary = home
            .appendingPathComponent("Library/Containers/com.niederme.AIQuota/Data/Library", isDirectory: true)
        let legacyWebKit = home
            .appendingPathComponent("Library/WebKit/com.niederme.AIQuota/WebsiteData/Default/legacy-origin", isDirectory: true)
        try fm.createDirectory(at: legacyWebKit, withIntermediateDirectories: true)
        let legacyMarker = legacyWebKit.appendingPathComponent("origin")
        try Data("legacy".utf8).write(to: legacyMarker)

        let suiteName = "LegacyWebKitMigrationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        LegacyWebKitMigration.migrateIfNeeded(
            bundleIdentifier: "com.niederme.AIQuota",
            currentDefaults: defaults,
            currentLibraryURL: currentLibrary,
            homeDirectoryURL: home,
            fileManager: fm
        )

        let copied = currentLibrary
            .appendingPathComponent("WebKit/WebsiteData/Default/legacy-origin/origin")
        #expect(fm.fileExists(atPath: copied.path))
        #expect(defaults.bool(forKey: "webkit.legacyStorageMigrated.v1"))
    }

    @Test("copies legacy cookies file into container cookies directory")
    func copiesLegacyCookies() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyWebKitMigrationTests-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let currentLibrary = home
            .appendingPathComponent("Library/Containers/com.niederme.AIQuota/Data/Library", isDirectory: true)
        let legacyCookies = home
            .appendingPathComponent("Library/Cookies", isDirectory: true)
        try fm.createDirectory(at: legacyCookies, withIntermediateDirectories: true)
        let legacyCookieFile = legacyCookies.appendingPathComponent("Cookies.binarycookies")
        try Data("cookie-data".utf8).write(to: legacyCookieFile)

        let suiteName = "LegacyWebKitMigrationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        LegacyWebKitMigration.migrateIfNeeded(
            bundleIdentifier: "com.niederme.AIQuota",
            currentDefaults: defaults,
            currentLibraryURL: currentLibrary,
            homeDirectoryURL: home,
            fileManager: fm
        )

        let copied = currentLibrary.appendingPathComponent("Cookies/Cookies.binarycookies")
        #expect(fm.fileExists(atPath: copied.path))
        #expect((try? Data(contentsOf: copied)) == Data("cookie-data".utf8))
    }
}
