import Foundation

public enum LegacyDefaultsMigration {
    private static let migratedKey = "defaults.legacyPrefsMigrated.v1"
    private static let migratedKeys = [
        "app.installedAt.v2",
        "onboarding.v1.hasCompleted",
        "codex.signedOutByUser",
        "claude.signedOutByUser",
    ]

    public static func migrateIfNeeded(
        bundleIdentifier: String,
        currentDefaults: UserDefaults = .standard,
        legacyPlistURL: URL? = nil
    ) {
        guard !currentDefaults.bool(forKey: migratedKey) else { return }

        let plistURL = legacyPlistURL
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Preferences/\(bundleIdentifier).plist")

        defer { currentDefaults.set(true, forKey: migratedKey) }

        guard let legacy = NSDictionary(contentsOf: plistURL) as? [String: Any] else { return }

        for key in migratedKeys where currentDefaults.object(forKey: key) == nil {
            guard let value = legacy[key] else { continue }
            currentDefaults.set(value, forKey: key)
        }
    }
}
