import SwiftUI
import WidgetKit
import AppIntents
import MobileAccessCore

extension QuotaService: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Service")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.codex: "Codex", .claude: "Claude"]
}
struct QuotaConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "AI allowance"
    static let description = IntentDescription("Your available allowance windows.")
    @Parameter(title: "Service", default: .codex) var service: QuotaService
}
struct QuotaEntry: TimelineEntry {
    let date: Date
    let values: [ProviderReading]
}
private func hasSavedCredentials(_ store: SharedQuotaStore) -> Bool {
    switch store.service {
    case .codex: return (try? store.load(CodexTokens.self)) != nil
    case .claude: return (try? store.load(ClaudeTokens.self)) != nil
    }
}
private func loadReading(_ service: QuotaService) async -> ProviderReading {
    if DemoQuotaData.isEnabled {
        return ProviderReading(service: service, reading: DemoQuotaData.reading(service), needsApp: false)
    }
    let store = SharedQuotaStore(service)
    do {
        let reading = try await store.fetch(source: "widget", minimumAge: 60)
        return ProviderReading(service: service, reading: reading, needsApp: false)
    } catch {
        let reconnect = (error as? AccessError) == .expired || (error as? AccessError) == .http(401)
            || (error as? ClaudeAccessError)?.requiresReconnect == true
            || SharedQuotaStore.Failure.classify(error) == .renewal
        return ProviderReading(service: service, reading: store.reading(), needsApp: reconnect && (hasSavedCredentials(store) || store.reading() != nil))
    }
}
private func snapshotReading(_ service: QuotaService) -> ProviderReading {
    if DemoQuotaData.isEnabled {
        return ProviderReading(service: service, reading: DemoQuotaData.reading(service), needsApp: false)
    }
    let store = SharedQuotaStore(service)
    return ProviderReading(service: service, reading: store.reading(), needsApp: store.failure().map { $0 != .temporary } ?? false)
}
private func timeline(_ values: [ProviderReading]) -> Timeline<QuotaEntry> {
    let now = Date.now
    let dates = Array(Set([now] + values.flatMap { WidgetFreshness.boundaries($0.reading, after: now) })).sorted()
    for value in values where !DemoQuotaData.isEnabled {
        SharedQuotaStore(value.service).log("widget", "timeline_handoff", reading: value.reading, entryDates: dates)
    }
    return Timeline(entries: dates.map { QuotaEntry(date: $0, values: values) }, policy: .after(now.addingTimeInterval(5 * 60)))
}
struct CodexProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: .now, values: [ProviderReading(service: .codex, reading: nil, needsApp: false)]) }
    func snapshot(for configuration: QuotaConfiguration, in context: Context) async -> QuotaEntry {
        QuotaEntry(date: .now, values: [snapshotReading(configuration.service)])
    }
    func timeline(for configuration: QuotaConfiguration, in context: Context) async -> Timeline<QuotaEntry> {
        await makeTimeline(configuration.service)
    }
    private func makeTimeline(_ service: QuotaService) async -> Timeline<QuotaEntry> {
        let value = await loadReading(service)
        return WidgetTimeline.make([value])
    }
}
// A namespace avoids colliding with TimelineProvider's required timeline method.
private enum WidgetTimeline {
    static func make(_ values: [ProviderReading]) -> Timeline<QuotaEntry> { timeline(values) }
}
struct BothConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Codex and Claude"
}
struct BothProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: .now, values: QuotaService.allCases.map { ProviderReading(service: $0, reading: nil, needsApp: false) }) }
    func snapshot(for configuration: BothConfiguration, in context: Context) async -> QuotaEntry {
        QuotaEntry(date: .now, values: QuotaService.allCases.map { snapshotReading($0) })
    }
    func timeline(for configuration: BothConfiguration, in context: Context) async -> Timeline<QuotaEntry> {
        async let codex = loadReading(.codex)
        async let claude = loadReading(.claude)
        return WidgetTimeline.make(await [codex, claude])
    }
}
struct SingleLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CodexLockScreen", intent: QuotaConfiguration.self, provider: CodexProvider()) { entry in
            if let value = entry.values.first {
                CodexDial(value: value, date: entry.date, logoScale: 0.8)
                    .widgetURL(URL(string: "aiquota-probe://overview"))
                    .containerBackground(for: .widget) { Color.clear }
            }
        }
        .configurationDisplayName("AI allowance")
        .description("Choose Codex or Claude. Shows the allowance windows reported by your account.")
        .supportedFamilies([.accessoryCircular])
    }
}
struct BothLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "BothLockScreen", intent: BothConfiguration.self, provider: BothProvider()) { entry in
            GeometryReader { geometry in
                let gap: CGFloat = 4
                let diameter = min(geometry.size.height, max(0, (geometry.size.width - gap) / 2))
                HStack(spacing: gap) {
                    ForEach(entry.values, id: \.service) { value in
                        Link(destination: URL(string: "aiquota-probe://overview")!) { CodexDial(value: value, date: entry.date, logoScale: 0.8) }
                            .frame(width: diameter, height: diameter)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Codex and Claude")
        .description("Both services, with the allowance windows reported by each account.")
        .supportedFamilies([.accessoryRectangular])
    }
}
enum CompactServices: String, AppEnum {
    case both, codex, claude
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Services")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.both: "Codex and Claude", .codex: "Codex", .claude: "Claude"]
    var services: [QuotaService] { self == .both ? [.codex, .claude] : self == .codex ? [.codex] : [.claude] }
}
struct CompactConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Allowance details"
    @Parameter(title: "Services", default: .both) var services: CompactServices
}
struct CompactProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: .now, values: [.init(service: .codex, reading: nil, needsApp: false), .init(service: .claude, reading: nil, needsApp: false)])
    }
    func snapshot(for configuration: CompactConfiguration, in context: Context) async -> QuotaEntry {
        QuotaEntry(date: .now, values: configuration.services.services.map { snapshotReading($0) })
    }
    func timeline(for configuration: CompactConfiguration, in context: Context) async -> Timeline<QuotaEntry> {
        if configuration.services == .both {
            async let codex = loadReading(.codex)
            async let claude = loadReading(.claude)
            return WidgetTimeline.make(await [codex, claude])
        }
        return WidgetTimeline.make([await loadReading(configuration.services.services[0])])
    }
}
struct CompactLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CompactLockScreen", intent: CompactConfiguration.self, provider: CompactProvider()) { entry in
            HStack(alignment: .center, spacing: 10) {
                ForEach(entry.values, id: \.service) { value in
                    CompactQuotaView(service: value.service, reading: value.reading, needsApp: value.needsApp, date: entry.date, compact: entry.values.count > 1)
                }
            }
            .widgetURL(URL(string: "aiquota-probe://overview"))
            .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Allowance details")
        .description("Gauges and percentages for Codex, Claude, or both, including monthly allowances.")
        .supportedFamilies([.accessoryRectangular])
    }
}
@main struct QuotaWidgets: WidgetBundle {
    var body: some Widget { SingleLockScreenWidget(); BothLockScreenWidget(); CompactLockScreenWidget(); ServiceDetailsWidget(); SingleHomeScreenWidget(); BothHomeScreenWidget() }
}

struct ServiceDetailsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ServiceDetails", intent: QuotaConfiguration.self, provider: CodexProvider()) { entry in
            if let value = entry.values.first {
                ServiceDetailsView(value: value, date: entry.date)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .widgetURL(URL(string: "aiquota-probe://overview"))
                .containerBackground(for: .widget) { Color.clear }
            }
        }
        .configurationDisplayName("Service details")
        .description("One service with a gauge and both percentages. Choose Codex or Claude.")
        .supportedFamilies([.accessoryRectangular])
    }
}

private struct HomeEntryView: View {
    let entry: QuotaEntry
    let both: Bool
    @Environment(\.widgetFamily) private var family
    var body: some View {
        HomeQuotaView(values: entry.values, date: entry.date,
            layout: both ? (family == .systemLarge ? .large : .dualMedium) : (family == .systemSmall ? .small : .singleMedium))
    }
}
struct SingleHomeScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AIQuotaHomeSingle", intent: QuotaConfiguration.self, provider: CodexProvider()) { entry in
            HomeEntryView(entry: entry, both: false)
                .widgetURL(entry.values.first?.service.url)
                .containerBackground(for: .widget) { HomeWidgetBackground() }
        }
        .configurationDisplayName("AI Quota")
        .description("Track your AI service usage quota. Choose Codex or Claude Code.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
struct BothHomeScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AIQuotaHomeBoth", intent: BothConfiguration.self, provider: BothProvider()) { entry in
            HomeEntryView(entry: entry, both: true)
                .widgetURL(URL(string: "aiquota-probe://overview"))
                .containerBackground(for: .widget) { HomeWidgetBackground() }
        }
        .configurationDisplayName("AI Quota")
        .description("Track both Codex and Claude Code with room for more detail.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
