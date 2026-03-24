import Foundation

public enum LegacyWebKitMigration {
    private static let migratedKey = "webkit.legacyStorageMigrated.v1"

    public static func migrateIfNeeded(
        bundleIdentifier: String,
        currentDefaults: UserDefaults = .standard,
        currentLibraryURL: URL? = nil,
        homeDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        guard !currentDefaults.bool(forKey: migratedKey) else { return }

        let currentLibrary = currentLibraryURL
            ?? fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
        let homeDirectory = homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
        guard let currentLibrary else {
            currentDefaults.set(true, forKey: migratedKey)
            return
        }

        let legacyLibrary = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        let legacyWebKit = legacyLibrary
            .appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
        let currentWebKit = currentLibrary.appendingPathComponent("WebKit", isDirectory: true)

        let legacyCookies = legacyLibrary
            .appendingPathComponent("Cookies", isDirectory: true)
            .appendingPathComponent("Cookies.binarycookies", isDirectory: false)
        let currentCookies = currentLibrary
            .appendingPathComponent("Cookies", isDirectory: true)
            .appendingPathComponent("Cookies.binarycookies", isDirectory: false)

        defer { currentDefaults.set(true, forKey: migratedKey) }

        guard legacyWebKit.path != currentWebKit.path || legacyCookies.path != currentCookies.path else {
            return
        }

        if fileManager.fileExists(atPath: legacyWebKit.path) {
            try? fileManager.removeItem(at: currentWebKit)
            try? fileManager.createDirectory(
                at: currentWebKit.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.copyItem(at: legacyWebKit, to: currentWebKit)
        }

        if fileManager.fileExists(atPath: legacyCookies.path) {
            try? fileManager.createDirectory(
                at: currentCookies.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.removeItem(at: currentCookies)
            try? fileManager.copyItem(at: legacyCookies, to: currentCookies)
        }
    }
}
