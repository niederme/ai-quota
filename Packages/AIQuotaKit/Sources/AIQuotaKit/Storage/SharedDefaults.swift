import Foundation

public enum SharedDefaults {
    private static let suite = "group.com.aiquota.shared"
    private static let usageKey = "cachedCodexUsage"
    private static let settingsKey = "appSettings"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suite) ?? .standard
    }

    public static func saveUsage(_ usage: CodexUsage) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: usageKey)
    }

    public static func loadCachedUsage() -> CodexUsage? {
        guard let data = defaults.data(forKey: usageKey) else { return nil }
        return try? JSONDecoder().decode(CodexUsage.self, from: data)
    }

    public static func saveSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }

    public static func loadSettings() -> AppSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return .default }
        return settings
    }
}
