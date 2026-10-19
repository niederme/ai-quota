import WidgetKit
import AppIntents
import AIQuotaKit
import MobileAccessCore

struct QuotaEntry: TimelineEntry {
    let date: Date
    let codexUsage: CodexUsage?
    let claudeUsage: ClaudeUsage?
    let devinUsage: DevinUsage?
    let configuration: ConfigurationAppIntent
    let enrolledServices: Set<ServiceType>

    // Backward-compat alias
    var usage: CodexUsage? { codexUsage }

    static let placeholder = QuotaEntry(
        date: .now,
        codexUsage: .placeholder,
        claudeUsage: .placeholder,
        devinUsage: .placeholder,
        configuration: ConfigurationAppIntent(),
        enrolledServices: [.codex, .claude]
    )
    static let empty = QuotaEntry(
        date: .now,
        codexUsage: nil,
        claudeUsage: nil,
        devinUsage: nil,
        configuration: ConfigurationAppIntent(),
        enrolledServices: []
    )
}

private extension ServiceOption {
    var serviceType: ServiceType {
        switch self {
        case .codex: return .codex
        case .claude: return .claude
        case .devin: return .devin
        }
    }
}

private func snapshotCodexUsage(
    _ usage: CodexUsage?,
    configuration: ConfigurationAppIntent?,
    enrolledServices: Set<ServiceType>
) -> CodexUsage? {
    if let usage { return usage }
    if let configuration {
        return configuration.service.serviceType == .codex && enrolledServices.contains(.codex) ? .placeholder : nil
    }
    return enrolledServices.contains(.codex) ? .placeholder : nil
}

private func snapshotClaudeUsage(
    _ usage: ClaudeUsage?,
    configuration: ConfigurationAppIntent?,
    enrolledServices: Set<ServiceType>
) -> ClaudeUsage? {
    if let usage { return usage }
    if let configuration {
        return configuration.service.serviceType == .claude && enrolledServices.contains(.claude) ? .placeholder : nil
    }
    return enrolledServices.contains(.claude) ? .placeholder : nil
}

private func snapshotDevinUsage(
    _ usage: DevinUsage?,
    configuration: ConfigurationAppIntent?,
    enrolledServices: Set<ServiceType>
) -> DevinUsage? {
    if let usage { return usage }
    if let configuration {
        return configuration.service.serviceType == .devin && enrolledServices.contains(.devin) ? .placeholder : nil
    }
    return enrolledServices.contains(.devin) ? .placeholder : nil
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
        let enrolledServices = SharedDefaults.loadEnrolledServices()
        completion(QuotaEntry(
            date: .now,
            codexUsage: snapshotCodexUsage(
                SharedDefaults.loadCachedUsage(),
                configuration: nil,
                enrolledServices: enrolledServices
            ),
            claudeUsage: snapshotClaudeUsage(
                SharedDefaults.loadCachedClaudeUsage(),
                configuration: nil,
                enrolledServices: enrolledServices
            ),
            devinUsage: snapshotDevinUsage(
                SharedDefaults.loadCachedDevinUsage(),
                configuration: nil,
                enrolledServices: enrolledServices
            ),
            configuration: ConfigurationAppIntent(),
            enrolledServices: enrolledServices
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
                devinUsage: snapshot.devinUsage,
                configuration: ConfigurationAppIntent(),
                enrolledServices: SharedDefaults.loadEnrolledServices()
            )
            let nextRefresh = WidgetRefreshPolicy.nextTimelineDate(
                codex: snapshot.codexUsage,
                claude: snapshot.claudeUsage,
                devin: snapshot.devinUsage
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
        let enrolledServices = SharedDefaults.loadEnrolledServices()
        return QuotaEntry(
            date: .now,
            codexUsage: snapshotCodexUsage(
                SharedDefaults.loadCachedUsage(),
                configuration: configuration,
                enrolledServices: enrolledServices
            ),
            claudeUsage: snapshotClaudeUsage(
                SharedDefaults.loadCachedClaudeUsage(),
                configuration: configuration,
                enrolledServices: enrolledServices
            ),
            devinUsage: snapshotDevinUsage(
                SharedDefaults.loadCachedDevinUsage(),
                configuration: configuration,
                enrolledServices: enrolledServices
            ),
            configuration: configuration,
            enrolledServices: enrolledServices
        )
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<QuotaEntry> {
        let snapshot = await loadSnapshot(forceRefresh: false)
        let entry = QuotaEntry(
            date: .now,
            codexUsage: snapshot.codexUsage,
            claudeUsage: snapshot.claudeUsage,
            devinUsage: snapshot.devinUsage,
            configuration: configuration,
            enrolledServices: SharedDefaults.loadEnrolledServices()
        )
        let nextRefresh = WidgetRefreshPolicy.nextTimelineDate(
            codex: snapshot.codexUsage,
            claude: snapshot.claudeUsage,
            devin: snapshot.devinUsage
        )
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}

private func loadSnapshot(forceRefresh: Bool) async -> WidgetRefreshSnapshot {
    let refreshService = WidgetRefreshService()
    return await refreshService.refreshAvailableServices(force: forceRefresh)
}
