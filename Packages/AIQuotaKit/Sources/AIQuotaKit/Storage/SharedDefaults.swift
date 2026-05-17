import Foundation

public enum SharedDefaults {
    private static let suite = "group.com.niederme.AIQuota"
    private static let codexUsageKey   = "cachedCodexUsage"
    private static let claudeUsageKey  = "cachedClaudeUsage"
    private static let claudeUsageSchemaVersionKey = "cachedClaudeUsageSchemaVersion"
    private static let currentClaudeUsageSchemaVersion = 2
    private static let claudeSourceAttemptsKey = "claudeSourceAttempts"
    private static let settingsKey     = "appSettings"
    private static let maxClaudeSourceAttempts = 10

    private static var defaults: UserDefaults {
        if let d = UserDefaults(suiteName: suite) { return d }
        print("⚠️ [SharedDefaults] App Group '\(suite)' unavailable — falling back to .standard (widget won't see data)")
        return .standard
    }

    /// WidgetKit can reload before app-group defaults are flushed cross-process.
    /// Force persistence so the widget extension sees the latest snapshot.
    private static func persistChanges() {
        defaults.synchronize()
    }

    // MARK: - Codex usage

    public static func saveUsage(_ usage: CodexUsage) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: codexUsageKey)
        persistChanges()
    }

    public static func loadCachedUsage() -> CodexUsage? {
        guard let data = defaults.data(forKey: codexUsageKey) else { return nil }
        return try? JSONDecoder().decode(CodexUsage.self, from: data)
    }

    public static func clearUsage() {
        defaults.removeObject(forKey: codexUsageKey)
        persistChanges()
    }

    // MARK: - Claude usage

    public static func saveClaudeUsage(_ usage: ClaudeUsage) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: claudeUsageKey)
        defaults.set(currentClaudeUsageSchemaVersion, forKey: claudeUsageSchemaVersionKey)
        persistChanges()
    }

    public static func loadCachedClaudeUsage() -> ClaudeUsage? {
        guard defaults.integer(forKey: claudeUsageSchemaVersionKey) >= currentClaudeUsageSchemaVersion else {
            clearClaudeUsage()
            return nil
        }
        guard let data = defaults.data(forKey: claudeUsageKey) else { return nil }
        return try? JSONDecoder().decode(ClaudeUsage.self, from: data)
    }

    public static func clearClaudeUsage() {
        defaults.removeObject(forKey: claudeUsageKey)
        defaults.removeObject(forKey: claudeUsageSchemaVersionKey)
        persistChanges()
    }

    public static func appendClaudeSourceAttempt(_ attempt: ClaudeSourceAttempt) {
        var attempts = loadClaudeSourceAttempts()
        attempts.append(attempt)
        if attempts.count > maxClaudeSourceAttempts {
            attempts.removeFirst(attempts.count - maxClaudeSourceAttempts)
        }
        guard let data = try? JSONEncoder().encode(attempts) else { return }
        defaults.set(data, forKey: claudeSourceAttemptsKey)
        persistChanges()
    }

    public static func loadClaudeSourceAttempts() -> [ClaudeSourceAttempt] {
        guard let data = defaults.data(forKey: claudeSourceAttemptsKey),
              let attempts = try? JSONDecoder().decode([ClaudeSourceAttempt].self, from: data)
        else { return [] }
        return attempts
    }

    public static func clearClaudeSourceAttempts() {
        defaults.removeObject(forKey: claudeSourceAttemptsKey)
        persistChanges()
    }

    // MARK: - Settings

    public static func saveSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
        persistChanges()
    }

    public static func loadSettings() -> AppSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return .default }
        return settings
    }

    // MARK: - Enrolled services

    private static let enrolledServicesKey = "enrolledServices"

    public static func loadEnrolledServices() -> Set<ServiceType> {
        guard let data = defaults.data(forKey: enrolledServicesKey),
              let rawValues = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(rawValues.compactMap { ServiceType(rawValue: $0) })
    }

    public static func saveEnrolledServices(_ services: Set<ServiceType>) {
        guard let data = try? JSONEncoder().encode(services.map(\.rawValue)) else { return }
        defaults.set(data, forKey: enrolledServicesKey)
        persistChanges()
    }

    public static func enrollService(_ service: ServiceType) {
        var current = loadEnrolledServices()
        current.insert(service)
        saveEnrolledServices(current)
    }

    public static func unenrollService(_ service: ServiceType) {
        var current = loadEnrolledServices()
        current.remove(service)
        saveEnrolledServices(current)
    }

    public static func clearEnrolledServices() {
        defaults.removeObject(forKey: enrolledServicesKey)
        persistChanges()
    }
}
