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
    static let description = IntentDescription("Five-hour and weekly allowance used.")
    @Parameter(title: "Service", default: .codex) var service: QuotaService
}
struct QuotaEntry: TimelineEntry {
    let date: Date
    let values: [ProviderReading]
}
private func loadReading(_ service: QuotaService) async -> ProviderReading {
    let store = SharedQuotaStore(service)
    do {
        let reading = try await store.fetch(source: "widget", minimumAge: 60)
        return ProviderReading(service: service, reading: reading, needsApp: false)
    } catch {
        let reconnect = (error as? AccessError) == .expired || (error as? AccessError) == .http(401)
            || (error as? ClaudeAccessError)?.requiresReconnect == true
            || SharedQuotaStore.Failure.classify(error) == .renewal
        return ProviderReading(service: service, reading: store.reading(), needsApp: reconnect)
    }
}
private func timeline(_ values: [ProviderReading]) -> Timeline<QuotaEntry> {
    let now = Date.now
    let dates = Array(Set([now] + values.flatMap { WidgetFreshness.boundaries($0.reading, after: now) })).sorted()
    for value in values {
        SharedQuotaStore(value.service).log("widget", "timeline_handoff", reading: value.reading, entryDates: dates)
    }
    return Timeline(entries: dates.map { QuotaEntry(date: $0, values: values) }, policy: .after(now.addingTimeInterval(5 * 60)))
}
struct CodexProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: .now, values: [ProviderReading(service: .codex, reading: nil, needsApp: false)]) }
    func snapshot(for configuration: QuotaConfiguration, in context: Context) async -> QuotaEntry {
        QuotaEntry(date: .now, values: [ProviderReading(service: configuration.service, reading: SharedQuotaStore(configuration.service).reading(), needsApp: false)])
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
        QuotaEntry(date: .now, values: QuotaService.allCases.map { ProviderReading(service: $0, reading: SharedQuotaStore($0).reading(), needsApp: false) })
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
        .description("Choose Codex or Claude. Outer ring: 5 hours. Inner ring: 7 days.")
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
                        Link(destination: URL(string: "aiquota-probe://overview")!) { CodexDial(value: value, date: entry.date) }
                            .frame(width: diameter, height: diameter)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Codex and Claude")
        .description("Both services. Outer rings: 5 hours. Inner rings: 7 days.")
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
        QuotaEntry(date: .now, values: configuration.services.services.map { ProviderReading(service: $0, reading: SharedQuotaStore($0).reading(), needsApp: false) })
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
        .description("Gauges and percentages for Codex, Claude, or both. 5h in primary text; 7d in secondary text.")
        .supportedFamilies([.accessoryRectangular])
    }
}
@main struct QuotaWidgets: WidgetBundle {
    var body: some Widget { SingleLockScreenWidget(); BothLockScreenWidget(); CompactLockScreenWidget(); ServiceDetailsWidget() }
}

struct ServiceDetailsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ServiceDetails", intent: QuotaConfiguration.self, provider: CodexProvider()) { entry in
            if let value = entry.values.first {
                ServiceDetailsView(value: value, date: entry.date)
                .widgetURL(URL(string: "aiquota-probe://overview"))
                .containerBackground(for: .widget) { Color.clear }
            }
        }
        .configurationDisplayName("Service details")
        .description("One service with a gauge and both percentages. Choose Codex or Claude.")
        .supportedFamilies([.accessoryRectangular])
    }
}
