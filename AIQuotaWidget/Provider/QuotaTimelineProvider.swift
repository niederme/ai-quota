import WidgetKit
import AIQuotaKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let usage: CodexUsage?

    static let placeholder = QuotaEntry(date: .now, usage: .placeholder)
    static let empty = QuotaEntry(date: .now, usage: nil)
}

struct QuotaTimelineProvider: TimelineProvider {
    typealias Entry = QuotaEntry

    func placeholder(in context: Context) -> QuotaEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(QuotaEntry(date: .now, usage: SharedDefaults.loadCachedUsage()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let cached = SharedDefaults.loadCachedUsage()
        let entry = QuotaEntry(date: .now, usage: cached)

        // Refresh 15 min after last app fetch, or in 15 min if no data
        let base = cached?.fetchedAt ?? .now
        let nextRefresh = max(base.addingTimeInterval(15 * 60), Date.now.addingTimeInterval(60))

        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}
