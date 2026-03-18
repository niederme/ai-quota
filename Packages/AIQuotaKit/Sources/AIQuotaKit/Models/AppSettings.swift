import Foundation

public struct AppSettings: Codable, Sendable, Equatable {
    public var refreshIntervalMinutes: Int

    public static let `default` = AppSettings(
        refreshIntervalMinutes: 15
    )

    public init(refreshIntervalMinutes: Int) {
        self.refreshIntervalMinutes = refreshIntervalMinutes
    }

    public var refreshInterval: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }
}
