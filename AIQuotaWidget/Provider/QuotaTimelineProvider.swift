import WidgetKit
import AppIntents
import AIQuotaKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let codexUsage: CodexUsage?
    let claudeUsage: ClaudeUsage?
    let configuration: ConfigurationAppIntent
    let enrolledServices: Set<ServiceType>

    // Backward-compat alias
    var usage: CodexUsage? { codexUsage }

    static let placeholder = QuotaEntry(
        date: .now,
        codexUsage: .placeholder,
        claudeUsage: .placeholder,
        configuration: ConfigurationAppIntent(),
        enrolledServices: [.codex, .claude]
    )
    static let empty = QuotaEntry(
        date: .now,
        codexUsage: nil,
        claudeUsage: nil,
        configuration: ConfigurationAppIntent(),
        enrolledServices: []
    )
}

private final class TimelineCompletionBox: @unchecked Sendable {
    let completion: (Timeline<QuotaEntry>) -> Void

    init(_ completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        self.completion = completion
    }
}

/// Static provider for the medium widget — keeps existing widget instances valid
/// while still allowing async fetches via an internal task.
struct StaticQuotaTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(QuotaEntry(
            date: .now,
            codexUsage: SharedDefaults.loadCachedUsage(),
            claudeUsage: SharedDefaults.loadCachedClaudeUsage(),
            configuration: ConfigurationAppIntent(),
            enrolledServices: SharedDefaults.loadEnrolledServices()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let completionBox = TimelineCompletionBox(completion)
        Task {
            let snapshot = await loadSnapshot(forceRefresh: false)
            let entry = QuotaEntry(
                date: .now,
                codexUsage: snapshot.codexUsage,
                claudeUsage: snapshot.claudeUsage,
                configuration: ConfigurationAppIntent(),
                enrolledServices: SharedDefaults.loadEnrolledServices()
            )
            let nextRefresh = WidgetRefreshPolicy.nextTimelineDate(
                codex: snapshot.codexUsage,
                claude: snapshot.claudeUsage
            )
            completionBox.completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}

struct QuotaTimelineProvider: AppIntentTimelineProvider {
    typealias Entry  = QuotaEntry
    typealias Intent = ConfigurationAppIntent

    func placeholder(in context: Context) -> QuotaEntry { .placeholder }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> QuotaEntry {
        QuotaEntry(
            date: .now,
            codexUsage: SharedDefaults.loadCachedUsage(),
            claudeUsage: SharedDefaults.loadCachedClaudeUsage(),
            configuration: configuration,
            enrolledServices: SharedDefaults.loadEnrolledServices()
        )
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<QuotaEntry> {
        let snapshot = await loadSnapshot(forceRefresh: false)
        let entry = QuotaEntry(
            date: .now,
            codexUsage: snapshot.codexUsage,
            claudeUsage: snapshot.claudeUsage,
            configuration: configuration,
            enrolledServices: SharedDefaults.loadEnrolledServices()
        )
        let nextRefresh = WidgetRefreshPolicy.nextTimelineDate(
            codex: snapshot.codexUsage,
            claude: snapshot.claudeUsage
        )
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}

private func loadSnapshot(forceRefresh: Bool) async -> WidgetRefreshSnapshot {
    let refreshService = WidgetRefreshService()
    return await refreshService.refreshAvailableServices(force: forceRefresh)
}
