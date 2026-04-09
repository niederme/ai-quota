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

    // MARK: - Aggregate computed properties (UI consolidation)
    // Each property covers one window type's threshold alerts (at-%, limit reached).
    // Reads true if any underlying field is on; writes all three simultaneously.

    public var codex5hThresholdAlerts: Bool {
        get { codex5hAt15 || codex5hAt5 || codex5hLimitReached }
        set { codex5hAt15 = newValue; codex5hAt5 = newValue; codex5hLimitReached = newValue }
    }

    public var codexWeeklyThresholdAlerts: Bool {
        get { codexAt15 || codexAt5 || codexLimitReached }
        set { codexAt15 = newValue; codexAt5 = newValue; codexLimitReached = newValue }
    }

    public var claude5hThresholdAlerts: Bool {
        get { claude5hAt15 || claude5hAt5 || claude5hLimitReached }
        set { claude5hAt15 = newValue; claude5hAt5 = newValue; claude5hLimitReached = newValue }
    }

    public var claude7dThresholdAlerts: Bool {
        get { claude7dAt80 || claude7dAt95 || claude7dLimitReached }
        set { claude7dAt80 = newValue; claude7dAt95 = newValue; claude7dLimitReached = newValue }
    }

    // MARK: - Migration

    /// Normalises any threshold group where the three underlying booleans are not all
    /// the same value. Mixed groups are resolved to their OR result (any=true → all-true).
    /// Call once on app launch before UI renders; subsequent interactions use the
    /// aggregate computed properties above which always write all three uniformly.
    public mutating func normalizeThresholds() {
        func normalize(_ a: inout Bool, _ b: inout Bool, _ c: inout Bool) {
            let resolved = a || b || c
            if a != resolved || b != resolved || c != resolved {
                a = resolved; b = resolved; c = resolved
            }
        }
        normalize(&codex5hAt15,  &codex5hAt5,  &codex5hLimitReached)
        normalize(&codexAt15,    &codexAt5,    &codexLimitReached)
        normalize(&claude5hAt15, &claude5hAt5, &claude5hLimitReached)
        normalize(&claude7dAt80, &claude7dAt95, &claude7dLimitReached)
    }
}

// MARK: - AppSettings

public struct AppSettings: Codable, Sendable, Equatable {
    public var refreshIntervalMinutes: Int
    public var notifications: NotificationPreferences
    /// Which service's gauge shows in the menu bar when multiple are signed in.
    public var menuBarService: ServiceType
    /// Whether the user opted into anonymous usage analytics.
    public var analyticsEnabled: Bool

    public static let `default` = AppSettings(
        refreshIntervalMinutes: 15,
        notifications: NotificationPreferences(),
        menuBarService: .codex,
        analyticsEnabled: false
    )

    public init(
        refreshIntervalMinutes: Int,
        notifications: NotificationPreferences = NotificationPreferences(),
        menuBarService: ServiceType = .codex,
        analyticsEnabled: Bool = false
    ) {
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.notifications = notifications
        self.menuBarService = menuBarService
        self.analyticsEnabled = analyticsEnabled
    }

    /// Migration-safe decoder: unknown keys are ignored, missing keys use defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        refreshIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? 15
        menuBarService = try c.decodeIfPresent(ServiceType.self, forKey: .menuBarService) ?? .codex
        notifications = try c.decodeIfPresent(NotificationPreferences.self, forKey: .notifications)
            ?? NotificationPreferences()
        analyticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .analyticsEnabled) ?? false
        // Legacy key `notificationsEnabled` is intentionally not migrated —
        // the default (all on) is the right starting point for all users.
    }

    public var refreshInterval: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }
}
