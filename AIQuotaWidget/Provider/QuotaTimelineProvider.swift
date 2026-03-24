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

/// Static provider for the medium widget — no intent, always shows both services.
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
        let codex  = SharedDefaults.loadCachedUsage()
        let claude = SharedDefaults.loadCachedClaudeUsage()
        let entry  = QuotaEntry(date: .now, codexUsage: codex, claudeUsage: claude, configuration: ConfigurationAppIntent(), enrolledServices: SharedDefaults.loadEnrolledServices())
        let mostRecent = [codex?.fetchedAt, claude?.fetchedAt].compactMap { $0 }.max() ?? .now
        let nextRefresh = max(mostRecent.addingTimeInterval(15 * 60), Date.now.addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
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
        let codex  = SharedDefaults.loadCachedUsage()
        let claude = SharedDefaults.loadCachedClaudeUsage()
        let entry  = QuotaEntry(date: .now, codexUsage: codex, claudeUsage: claude, configuration: configuration, enrolledServices: SharedDefaults.loadEnrolledServices())

        // Refresh 15 min after the most-recent app fetch, or in 15 min if no data
        let mostRecent = [codex?.fetchedAt, claude?.fetchedAt].compactMap { $0 }.max() ?? .now
        let nextRefresh = max(mostRecent.addingTimeInterval(15 * 60), Date.now.addingTimeInterval(60))

        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}
