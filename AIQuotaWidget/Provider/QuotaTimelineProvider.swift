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

/// Async provider for the medium widget — always shows both services.
struct MediumQuotaTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = QuotaEntry
    typealias Intent = MediumConfigurationAppIntent

    func placeholder(in context: Context) -> QuotaEntry { .placeholder }

    func snapshot(for configuration: MediumConfigurationAppIntent, in context: Context) async -> QuotaEntry {
        QuotaEntry(
            date: .now,
            codexUsage: SharedDefaults.loadCachedUsage(),
            claudeUsage: SharedDefaults.loadCachedClaudeUsage(),
            configuration: ConfigurationAppIntent(),
            enrolledServices: SharedDefaults.loadEnrolledServices()
        )
    }

    func timeline(for configuration: MediumConfigurationAppIntent, in context: Context) async -> Timeline<QuotaEntry> {
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
        return Timeline(entries: [entry], policy: .after(nextRefresh))
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
