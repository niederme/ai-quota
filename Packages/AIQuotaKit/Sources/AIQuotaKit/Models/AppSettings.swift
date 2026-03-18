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

// MARK: - AppSettings

public struct AppSettings: Codable, Sendable, Equatable {
    public var refreshIntervalMinutes: Int
    public var notificationsEnabled: Bool
    /// Which service's gauge shows in the menu bar when multiple are signed in.
    public var menuBarService: ServiceType

    public static let `default` = AppSettings(
        refreshIntervalMinutes: 15,
        notificationsEnabled: true,
        menuBarService: .codex
    )

    public init(refreshIntervalMinutes: Int, notificationsEnabled: Bool, menuBarService: ServiceType = .codex) {
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.notificationsEnabled = notificationsEnabled
        self.menuBarService = menuBarService
    }

    public var refreshInterval: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }
}
