import WidgetKit
import AppIntents
import AIQuotaKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let codexUsage: CodexUsage?
    let claudeUsage: ClaudeUsage?
    let configuration: ConfigurationAppIntent

    // Backward-compat alias
    var usage: CodexUsage? { codexUsage }

    static let placeholder = QuotaEntry(
        date: .now,
        codexUsage: .placeholder,
        claudeUsage: .placeholder,
        configuration: ConfigurationAppIntent()
    )
    static let empty = QuotaEntry(
        date: .now,
        codexUsage: nil,
        claudeUsage: nil,
        configuration: ConfigurationAppIntent()
    )
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
            configuration: configuration
        )
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<QuotaEntry> {
        let codex  = SharedDefaults.loadCachedUsage()
        let claude = SharedDefaults.loadCachedClaudeUsage()
        let entry  = QuotaEntry(date: .now, codexUsage: codex, claudeUsage: claude, configuration: configuration)

        // Refresh 15 min after the most-recent app fetch, or in 15 min if no data
        let mostRecent = [codex?.fetchedAt, claude?.fetchedAt].compactMap { $0 }.max() ?? .now
        let nextRefresh = max(mostRecent.addingTimeInterval(15 * 60), Date.now.addingTimeInterval(60))

        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}
