import SwiftUI
import WidgetKit
import AppIntents
import MobileAccessCore

extension QuotaService: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Service")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.codex: "Codex", .claude: "Claude"]
}

struct WidgetAccount: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "AIQuota account")
    static let defaultQuery = WidgetAccountQuery()

    let id: String
    let profileID: String
    let service: QuotaService
    let label: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)", subtitle: "\(service.name)")
    }

    init(_ profile: AccountProfile) {
        id = "\(profile.service.rawValue):\(profile.id)"
        profileID = profile.id
        service = profile.service
        label = profile.label
    }
}

struct WidgetAccountQuery: EntityQuery {
    private let service: QuotaService?

    init() { service = nil }
    init(service: QuotaService) { self.service = service }

    func entities(for identifiers: [String]) async throws -> [WidgetAccount] {
        accounts.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetAccount] { accounts }

    private var accounts: [WidgetAccount] {
        let profiles = service.map(AccountRegistry.profiles(for:)) ?? AccountRegistry.all()
        return profiles.map(WidgetAccount.init)
    }
}

struct QuotaConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "AI allowance"
    static let description = IntentDescription("Your available allowance windows.")
    @Parameter(title: "Service", default: .codex) var service: QuotaService
    @Parameter(title: "Account") var account: WidgetAccount?
}
struct QuotaEntry: TimelineEntry {
    let date: Date
    let values: [ProviderReading]
    let accountLabels: [QuotaService: String]
}

private struct WidgetReading: Sendable {
    let value: ProviderReading
    let accountLabel: String?
    let namespace: String?
}

private func profile(_ selection: WidgetAccount?, for service: QuotaService) -> AccountProfile? {
    let profiles = AccountRegistry.profiles(for: service)
    if let selection, selection.service == service,
       let selected = profiles.first(where: { $0.id == selection.profileID }) {
        return selected
    }
    return AccountRegistry.defaultProfile(for: service)
}

private func entry(_ readings: [WidgetReading], at date: Date = .now) -> QuotaEntry {
    QuotaEntry(
        date: date,
        values: readings.map(\.value),
        accountLabels: Dictionary(uniqueKeysWithValues: readings.compactMap { reading in
            reading.accountLabel.map { (reading.value.service, $0) }
        })
    )
}
private func hasSavedCredentials(_ store: SharedQuotaStore) -> Bool {
    switch store.service {
    case .codex: return (try? store.load(CodexTokens.self)) != nil
    case .claude: return (try? store.load(ClaudeTokens.self)) != nil
    }
}
private func loadReading(_ service: QuotaService, account: WidgetAccount? = nil) async -> WidgetReading {
    guard let profile = profile(account, for: service) else {
        return WidgetReading(value: ProviderReading(service: service, reading: nil, needsApp: false), accountLabel: nil, namespace: nil)
    }
    if DemoQuotaData.isEnabled {
        return WidgetReading(value: ProviderReading(service: service, reading: DemoQuotaData.reading(service), needsApp: false), accountLabel: profile.label, namespace: profile.id)
    }
    let store = SharedQuotaStore(service, namespace: profile.id)
    do {
        let reading = try await store.fetch(source: "widget", minimumAge: 60)
        return WidgetReading(value: ProviderReading(service: service, reading: reading, needsApp: false), accountLabel: profile.label, namespace: profile.id)
    } catch {
        let reconnect = (error as? AccessError) == .expired || (error as? AccessError) == .http(401)
            || (error as? ClaudeAccessError)?.requiresReconnect == true
            || SharedQuotaStore.Failure.classify(error) == .renewal
        let value = ProviderReading(service: service, reading: store.reading(), needsApp: reconnect && (hasSavedCredentials(store) || store.reading() != nil), updateFailed: true)
        return WidgetReading(value: value, accountLabel: profile.label, namespace: profile.id)
    }
}
private func snapshotReading(_ service: QuotaService, account: WidgetAccount? = nil) -> WidgetReading {
    guard let profile = profile(account, for: service) else {
        return WidgetReading(value: ProviderReading(service: service, reading: nil, needsApp: false), accountLabel: nil, namespace: nil)
    }
    if DemoQuotaData.isEnabled {
        return WidgetReading(value: ProviderReading(service: service, reading: DemoQuotaData.reading(service), needsApp: false), accountLabel: profile.label, namespace: profile.id)
    }
    let store = SharedQuotaStore(service, namespace: profile.id)
    let value = ProviderReading(service: service, reading: store.reading(), needsApp: store.failure().map { $0 != .temporary } ?? false, updateFailed: store.failure() != nil)
    return WidgetReading(value: value, accountLabel: profile.label, namespace: profile.id)
}
private func timeline(_ readings: [WidgetReading]) -> Timeline<QuotaEntry> {
    let now = Date.now
    let values = readings.map(\.value)
    let dates = Array(Set([now] + values.flatMap { WidgetFreshness.boundaries($0.reading, after: now) })).sorted()
    for reading in readings where !DemoQuotaData.isEnabled {
        guard let namespace = reading.namespace else { continue }
        SharedQuotaStore(reading.value.service, namespace: namespace).log("widget", "timeline_handoff", reading: reading.value.reading, entryDates: dates)
    }
    return Timeline(entries: dates.map { entry(readings, at: $0) }, policy: .after(now.addingTimeInterval(5 * 60)))
}
struct CodexProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: .now, values: [ProviderReading(service: .codex, reading: nil, needsApp: false)], accountLabels: [:]) }
    func snapshot(for configuration: QuotaConfiguration, in context: Context) async -> QuotaEntry {
        entry([snapshotReading(configuration.service, account: configuration.account)])
    }
    func timeline(for configuration: QuotaConfiguration, in context: Context) async -> Timeline<QuotaEntry> {
        await makeTimeline(configuration.service, account: configuration.account)
    }
    private func makeTimeline(_ service: QuotaService, account: WidgetAccount?) async -> Timeline<QuotaEntry> {
        let value = await loadReading(service, account: account)
        return WidgetTimeline.make([value])
    }
}
// A namespace avoids colliding with TimelineProvider's required timeline method.
private enum WidgetTimeline {
    static func make(_ values: [WidgetReading]) -> Timeline<QuotaEntry> { timeline(values) }
}
struct BothConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Codex and Claude"
    @Parameter(title: "Codex account", query: WidgetAccountQuery(service: .codex)) var codexAccount: WidgetAccount?
    @Parameter(title: "Claude account", query: WidgetAccountQuery(service: .claude)) var claudeAccount: WidgetAccount?
}
struct BothProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: .now, values: QuotaService.allCases.map { ProviderReading(service: $0, reading: nil, needsApp: false) }, accountLabels: [:]) }
    func snapshot(for configuration: BothConfiguration, in context: Context) async -> QuotaEntry {
        entry([snapshotReading(.codex, account: configuration.codexAccount), snapshotReading(.claude, account: configuration.claudeAccount)])
    }
    func timeline(for configuration: BothConfiguration, in context: Context) async -> Timeline<QuotaEntry> {
        async let codex = loadReading(.codex, account: configuration.codexAccount)
        async let claude = loadReading(.claude, account: configuration.claudeAccount)
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
    @Parameter(title: "Codex account", query: WidgetAccountQuery(service: .codex)) var codexAccount: WidgetAccount?
    @Parameter(title: "Claude account", query: WidgetAccountQuery(service: .claude)) var claudeAccount: WidgetAccount?
}
struct CompactProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: .now, values: [.init(service: .codex, reading: nil, needsApp: false), .init(service: .claude, reading: nil, needsApp: false)], accountLabels: [:])
    }
    func snapshot(for configuration: CompactConfiguration, in context: Context) async -> QuotaEntry {
        entry(configuration.services.services.map { service in
            snapshotReading(service, account: service == .codex ? configuration.codexAccount : configuration.claudeAccount)
        })
    }
    func timeline(for configuration: CompactConfiguration, in context: Context) async -> Timeline<QuotaEntry> {
        if configuration.services == .both {
            async let codex = loadReading(.codex, account: configuration.codexAccount)
            async let claude = loadReading(.claude, account: configuration.claudeAccount)
            return WidgetTimeline.make(await [codex, claude])
        }
        let service = configuration.services.services[0]
        return WidgetTimeline.make([await loadReading(service, account: service == .codex ? configuration.codexAccount : configuration.claudeAccount)])
    }
}
struct CompactLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CompactLockScreen", intent: CompactConfiguration.self, provider: CompactProvider()) { entry in
            HStack(alignment: .center, spacing: 2) {
                ForEach(entry.values, id: \.service) { value in
                    if entry.values.count == 1 {
                        ServiceDetailsView(value: value, date: entry.date)
                    } else {
                        CompactQuotaView(service: value.service, reading: value.reading, needsApp: value.needsApp, date: entry.date, compact: true, updateFailed: value.updateFailed)
                    }
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
        VStack(spacing: 0) {
            if family != .systemSmall, !entry.accountLabels.isEmpty {
                HStack(spacing: 8) {
                    ForEach(entry.values, id: \.service) { value in
                        if let label = entry.accountLabels[value.service] {
                            Text("\(value.service.name): \(label)")
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 7)
            }
            HomeQuotaView(values: entry.values, date: entry.date,
                layout: both ? (family == .systemLarge ? .large : .dualMedium) : (family == .systemSmall ? .small : .singleMedium))
        }
    }
}
struct SingleHomeScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AIQuotaHomeSingle", intent: QuotaConfiguration.self, provider: CodexProvider()) { entry in
            HomeEntryView(entry: entry, both: false)
                .widgetURL(entry.values.first?.service.url)
                .containerBackground(for: .widget) { HomeWidgetBackground() }
        }
        .configurationDisplayName("AIQuota")
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
        .configurationDisplayName("AIQuota")
        .description("Track both Codex and Claude Code with room for more detail.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
