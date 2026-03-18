import Foundation

public struct AppSettings: Codable, Sendable, Equatable {
    public var refreshIntervalMinutes: Int
    public var notificationsEnabled: Bool

    public static let `default` = AppSettings(
        refreshIntervalMinutes: 15,
        notificationsEnabled: true
    )

    public init(refreshIntervalMinutes: Int, notificationsEnabled: Bool) {
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.notificationsEnabled = notificationsEnabled
    }

    public var refreshInterval: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }
}
