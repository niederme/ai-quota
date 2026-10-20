import Foundation
import MobileAccessCore

public enum WidgetRefreshPolicy {
    public static let minimumTimelineInterval: TimeInterval = 60
    public static let heartbeatInterval: TimeInterval = 5 * 60
    public static let staleCacheInterval: TimeInterval = 5 * 60

    public static func shouldFetchFromNetwork(
        codex: CodexUsage?,
        claude: ClaudeUsage?,
        devin: DevinUsage? = nil,
        now: Date = .now
    ) -> Bool {
        guard let mostRecentFetch = [codex?.fetchedAt, claude?.fetchedAt, devin?.fetchedAt].compactMap({ $0 }).max() else {
            return true
        }
        return now.timeIntervalSince(mostRecentFetch) >= staleCacheInterval
    }

    public static func nextTimelineDate(
        codex: CodexUsage?,
        claude: ClaudeUsage?,
        devin: DevinUsage? = nil,
        now: Date = .now
    ) -> Date {
        let floor = now.addingTimeInterval(minimumTimelineInterval)
        guard codex != nil || claude != nil || devin != nil else { return floor }

        let heartbeat = now.addingTimeInterval(heartbeatInterval)

        let resetBoundaries = [
            codex?.hourlyResetAt,
            codex?.weeklyResetAt,
            claude?.fiveHourResetsAt,
            claude?.sevenDayResetsAt,
            devin?.dailyResetsAt,
            devin?.weeklyResetsAt,
        ]
            .compactMap { $0 }
            .filter { $0 > floor }

        return min(resetBoundaries.min() ?? heartbeat, heartbeat)
    }
}
