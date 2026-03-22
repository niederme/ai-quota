import Foundation

// MARK: - Service type

/// Which AI service to display.
public enum ServiceType: String, Codable, CaseIterable, Sendable {
    case codex  = "codex"   // OpenAI Codex via chatgpt.com
    case claude = "claude"  // Claude via claude.ai

    public var displayName: String {
        switch self {
        case .codex:  "Codex"
        case .claude: "Claude Code"
        }
    }

    public var iconName: String {
        switch self {
        case .codex:  "brain.fill"
        case .claude: "sparkles"
        }
    }
}

// MARK: - NotificationPreferences

public struct NotificationPreferences: Codable, Sendable, Equatable {
    // Master switch
    public var enabled: Bool = true

    // Per-service master switches
    public var codexEnabled: Bool = true
    public var claudeEnabled: Bool = true

    // Codex — 5-hour window
    public var codex5hAt15: Bool = true
    public var codex5hAt5: Bool = true
    public var codex5hLimitReached: Bool = true
    public var codex5hReset: Bool = true

    // Codex — weekly window
    public var codexAt15: Bool = true           // < 15% remaining
    public var codexAt5: Bool = true            // < 5% remaining
    public var codexLimitReached: Bool = true   // 0% (limit reached)
    public var codexReset: Bool = true          // weekly reset

    // Claude — 5-hour window
    public var claude5hAt15: Bool = true
    public var claude5hAt5: Bool = true
    public var claude5hLimitReached: Bool = true
    public var claude5hReset: Bool = true

    // Claude — 7-day window
    public var claude7dAt80: Bool = true        // 80% used
    public var claude7dAt95: Bool = true        // 95% used
    public var claude7dLimitReached: Bool = true
    public var claude7dReset: Bool = true

    public init() {}

    /// Migration-safe decoder: missing keys fall back to defaults rather than throwing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled              = try c.decodeIfPresent(Bool.self, forKey: .enabled)              ?? true
        codexEnabled         = try c.decodeIfPresent(Bool.self, forKey: .codexEnabled)         ?? true
        claudeEnabled        = try c.decodeIfPresent(Bool.self, forKey: .claudeEnabled)        ?? true
        codex5hAt15          = try c.decodeIfPresent(Bool.self, forKey: .codex5hAt15)          ?? true
        codex5hAt5           = try c.decodeIfPresent(Bool.self, forKey: .codex5hAt5)           ?? true
        codex5hLimitReached  = try c.decodeIfPresent(Bool.self, forKey: .codex5hLimitReached)  ?? true
        codex5hReset         = try c.decodeIfPresent(Bool.self, forKey: .codex5hReset)         ?? true
        codexAt15            = try c.decodeIfPresent(Bool.self, forKey: .codexAt15)            ?? true
        codexAt5             = try c.decodeIfPresent(Bool.self, forKey: .codexAt5)             ?? true
        codexLimitReached    = try c.decodeIfPresent(Bool.self, forKey: .codexLimitReached)    ?? true
        codexReset           = try c.decodeIfPresent(Bool.self, forKey: .codexReset)           ?? true
        claude5hAt15         = try c.decodeIfPresent(Bool.self, forKey: .claude5hAt15)         ?? true
        claude5hAt5          = try c.decodeIfPresent(Bool.self, forKey: .claude5hAt5)          ?? true
        claude5hLimitReached = try c.decodeIfPresent(Bool.self, forKey: .claude5hLimitReached) ?? true
        claude5hReset        = try c.decodeIfPresent(Bool.self, forKey: .claude5hReset)        ?? true
        claude7dAt80         = try c.decodeIfPresent(Bool.self, forKey: .claude7dAt80)         ?? true
        claude7dAt95         = try c.decodeIfPresent(Bool.self, forKey: .claude7dAt95)         ?? true
        claude7dLimitReached = try c.decodeIfPresent(Bool.self, forKey: .claude7dLimitReached) ?? true
        claude7dReset        = try c.decodeIfPresent(Bool.self, forKey: .claude7dReset)        ?? true
    }
}

// MARK: - AppSettings

public struct AppSettings: Codable, Sendable, Equatable {
    public var refreshIntervalMinutes: Int
    public var notifications: NotificationPreferences
    /// Which service's gauge shows in the menu bar when multiple are signed in.
    public var menuBarService: ServiceType

    public static let `default` = AppSettings(
        refreshIntervalMinutes: 15,
        notifications: NotificationPreferences(),
        menuBarService: .codex
    )

    public init(
        refreshIntervalMinutes: Int,
        notifications: NotificationPreferences = NotificationPreferences(),
        menuBarService: ServiceType = .codex
    ) {
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.notifications = notifications
        self.menuBarService = menuBarService
    }

    /// Migration-safe decoder: unknown keys are ignored, missing keys use defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        refreshIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? 15
        menuBarService = try c.decodeIfPresent(ServiceType.self, forKey: .menuBarService) ?? .codex
        notifications = try c.decodeIfPresent(NotificationPreferences.self, forKey: .notifications)
            ?? NotificationPreferences()
        // Legacy key `notificationsEnabled` is intentionally not migrated —
        // the default (all on) is the right starting point for all users.
    }

    public var refreshInterval: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }
}
