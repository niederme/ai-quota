import Foundation

public struct AppSettings: Codable, Sendable, Equatable {
    public var refreshIntervalMinutes: Int
    public var showPercentInMenuBar: Bool

    public static let `default` = AppSettings(
        refreshIntervalMinutes: 15,
        showPercentInMenuBar: true
    )

    public init(refreshIntervalMinutes: Int, showPercentInMenuBar: Bool) {
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.showPercentInMenuBar = showPercentInMenuBar
    }

    public var refreshInterval: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }
}
