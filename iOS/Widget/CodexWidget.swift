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
    let identityHint: String?
    let isAvailable: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)", subtitle: "\(pickerDetail)")
    }

    var pickerDetail: String {
        [service.name, identityHint].compactMap { $0 }.joined(separator: " · ")
    }

    init(_ profile: AccountProfile, identityHint: String?) {
        id = "\(profile.service.rawValue):\(profile.id)"
        profileID = profile.id
        service = profile.service
        label = profile.label
        self.identityHint = identityHint
        isAvailable = true
    }

    fileprivate init?(unavailableIdentifier identifier: String, requiredService: QuotaService? = nil) {
        guard let separator = identifier.firstIndex(of: ":"),
              let parsedService = QuotaService(rawValue: String(identifier[..<separator])) else { return nil }
        guard requiredService == nil || requiredService == parsedService else { return nil }
        let parsedID = String(identifier[identifier.index(after: separator)...])
        guard !parsedID.isEmpty else { return nil }
        id = identifier
        profileID = parsedID
        service = parsedService
        label = "Choose or reconnect"
        identityHint = nil
        isAvailable = false
    }

    static func make(_ profiles: [AccountProfile]) -> [WidgetAccount] {
        let groups = Dictionary(grouping: profiles) { normalizedLabel($0.label) }
        return profiles.map { profile in
            let collisions = groups[normalizedLabel(profile.label)] ?? []
            let hint = safeIdentityHint(profile.providerIdentity)
            guard collisions.count > 1 else { return WidgetAccount(profile, identityHint: hint) }

            let matchingHints = collisions.compactMap { safeIdentityHint($0.providerIdentity) }
            if let hint, matchingHints.filter({ $0.caseInsensitiveCompare(hint) == .orderedSame }).count == 1 {
                return WidgetAccount(profile, identityHint: hint)
            }
            return WidgetAccount(profile, identityHint: "account \(shortID(profile.id))")
        }
    }

    static func options(for service: QuotaService, profiles: [AccountProfile]) -> [WidgetAccount] {
        make(profiles.filter { $0.service == service })
    }

    static func soleDefault(in values: [WidgetAccount]) -> WidgetAccount? {
        values.count == 1 ? values[0] : nil
    }

    static func headerLabel(for profile: AccountProfile, among profiles: [AccountProfile]) -> String? {
        guard profiles.count > 1 else { return nil }
        let collisions = profiles.filter { normalizedLabel($0.label) == normalizedLabel(profile.label) }
        guard collisions.count > 1 else { return profile.label }
        let hint = safeIdentityHint(profile.providerIdentity)
        let matchingHints = collisions.compactMap { safeIdentityHint($0.providerIdentity) }
        if let hint, matchingHints.filter({ $0.caseInsensitiveCompare(hint) == .orderedSame }).count == 1 {
            return "\(profile.label) · \(hint)"
        }
        return "\(profile.label) · \(shortID(profile.id))"
    }

    private static func normalizedLabel(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func safeIdentityHint(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.count > 64 else { return cleaned }
        return "\(cleaned.prefix(30))…\(cleaned.suffix(30))"
    }

    private static func shortID(_ value: String) -> String {
        let suffix = value.suffix(6)
        return suffix.isEmpty ? "unknown" : String(suffix)
    }
}

struct WidgetAccountQuery: EntityQuery {
    private let service: QuotaService?

    init() { service = nil }
    init(service: QuotaService) { self.service = service }

    func entities(for identifiers: [String]) async throws -> [WidgetAccount] {
        let current = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        return identifiers.compactMap { identifier in
            current[identifier] ?? WidgetAccount(unavailableIdentifier: identifier, requiredService: service)
        }
    }

    func suggestedEntities() async throws -> [WidgetAccount] { accounts }
    func defaultResult() async -> WidgetAccount? { WidgetAccount.soleDefault(in: accounts) }

    private var accounts: [WidgetAccount] {
        let profiles = service.map(AccountRegistry.profiles(for:)) ?? AccountRegistry.all()
        return service.map { WidgetAccount.options(for: $0, profiles: profiles) } ?? WidgetAccount.make(profiles)
    }
}

private struct ServiceWidgetAccountOptionsProvider: DynamicOptionsProvider {
    let service: QuotaService

    func results() async throws -> [WidgetAccount] {
        WidgetAccount.options(for: service, profiles: AccountRegistry.profiles(for: service))
    }

    func defaultResult() async -> WidgetAccount? {
        WidgetAccount.soleDefault(in: WidgetAccount.options(for: service, profiles: AccountRegistry.profiles(for: service)))
    }
}

enum AccountWidgetShow: String, AppEnum {
    case chosenAccount, closestToLimit
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Show")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.chosenAccount: "Chosen account", .closestToLimit: "Closest to a limit"]
}
enum AccountsWidgetOrder: String, AppEnum {
    case closestToLimit, asListed
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Order")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.closestToLimit: "Closest to a limit", .asListed: "As listed"]
}

struct QuotaConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Account"
    static let description = IntentDescription("One chosen account, or the account closest to a limit.")
    @Parameter(title: "Show", default: .chosenAccount) var show: AccountWidgetShow
    @Parameter(title: "Service", default: .codex) var service: QuotaService
    @Parameter(title: "Account") var account: WidgetAccount?
    static var parameterSummary: some ParameterSummary {
        When(\.$show, .equalTo, .chosenAccount) { Summary { \.$show; \.$account } }
        otherwise: { Summary { \.$show } }
    }
}
struct QuotaEntry: TimelineEntry {
    let date: Date
    let values: [ProviderReading]
    let accountLabels: [QuotaService: String]
    var accountContents: [WidgetAccountContent]? = nil
    var accounts: [WidgetAccountContent] {
        accountContents ?? values.enumerated().map {
            WidgetAccountContent(id: "\($0.offset)", value: $0.element, label: accountLabels[$0.element.service] ?? "")
        }
    }
}

private struct WidgetReading: Sendable {
    let value: ProviderReading
    let accountLabel: String?
    let namespace: String?
    var content: WidgetAccountContent? = nil
}

enum WidgetProfileResolution: Equatable {
    case selected(AccountProfile, headerLabel: String?)
    case noAccount
    case unavailable
}

func resolveWidgetProfile(
    _ selection: WidgetAccount?,
    for service: QuotaService,
    profiles: [AccountProfile],
    defaultProfile: AccountProfile?
) -> WidgetProfileResolution {
    if let selection {
        guard selection.service == service, selection.isAvailable,
              let selected = profiles.first(where: { $0.id == selection.profileID }) else {
            return .unavailable
        }
        return .selected(selected, headerLabel: WidgetAccount.headerLabel(for: selected, among: profiles))
    }
    // Existing widgets predate account parameters. A nil selection retains the
    // former service default, while the editor only auto-selects a sole account.
    guard let migrated = defaultProfile else { return .noAccount }
    return .selected(migrated, headerLabel: WidgetAccount.headerLabel(for: migrated, among: profiles))
}

private func profile(_ selection: WidgetAccount?, for service: QuotaService) -> WidgetProfileResolution {
    let profiles = AccountRegistry.profiles(for: service)
    return resolveWidgetProfile(selection, for: service, profiles: profiles, defaultProfile: AccountRegistry.defaultProfile(for: service))
}

private func entry(_ readings: [WidgetReading], at date: Date = .now) -> QuotaEntry {
    var labels: [QuotaService: String] = [:]
    for reading in readings { if let label = reading.accountLabel { labels[reading.value.service] = label } }
    return QuotaEntry(date: date, values: readings.map(\.value), accountLabels: labels,
        accountContents: readings.enumerated().map { index, reading in
            reading.content ?? WidgetAccountContent(id: "\(reading.value.service.rawValue):\(reading.namespace ?? String(index))", value: reading.value, label: reading.accountLabel ?? "")
        })
}
private func enriched(_ reading: WidgetReading, selection: WidgetAccount?) -> WidgetReading {
    let store = reading.namespace.map { SharedQuotaStore(reading.value.service, namespace: $0) }
    let profile = AccountRegistry.profiles(for: reading.value.service).first { $0.id == reading.namespace }
    let history = store?.widgetHistory()
    let demo = DemoQuotaData.isEnabled
    return WidgetReading(value: reading.value, accountLabel: reading.accountLabel, namespace: reading.namespace,
        content: WidgetAccountContent(id: selection?.id ?? "\(reading.value.service.rawValue):\(reading.namespace ?? "empty")", value: reading.value,
            label: profile?.label ?? reading.accountLabel ?? "",
            tokenHistory: demo && reading.value.service == .codex ? DemoQuotaData.tokenHistory() : history?.tokens,
            usageHistory: demo && reading.value.service == .codex ? DemoQuotaData.history() : history?.usage))
}
private func ranked(_ readings: [WidgetReading]) -> [WidgetReading] {
    let order = WidgetAccountOrdering.closestFirst(readings.compactMap(\.content)).map(\.id)
    return order.compactMap { id in readings.first { $0.content?.id == id } }
}
private func accountReadings(_ selections: [WidgetAccount], fetch: Bool) async -> [WidgetReading] {
    if !fetch { return selections.map { enriched(snapshotReading($0.service, account: $0), selection: $0) } }
    return await withTaskGroup(of: (Int, WidgetReading).self) { group in
        for (index, account) in selections.enumerated() {
            group.addTask { (index, enriched(await loadReading(account.service, account: account), selection: account)) }
        }
        var result: [(Int, WidgetReading)] = []
        for await value in group { result.append(value) }
        return result.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
private func singleReadings(_ configuration: QuotaConfiguration, fetch: Bool) async -> [WidgetReading] {
    if configuration.show == .closestToLimit {
        let selections = WidgetAccount.make(AccountRegistry.all())
        let readings = await accountReadings(selections, fetch: fetch)
        if let first = ranked(readings).first { return [first] }
    }
    let service = configuration.account?.service ?? configuration.service
    if DemoQuotaData.isEnabled, configuration.account == nil {
        return [enriched(WidgetReading(value: .init(service: service, reading: DemoQuotaData.reading(service), needsApp: false), accountLabel: nil, namespace: nil), selection: nil)]
    }
    let reading = fetch ? await loadReading(service, account: configuration.account) : snapshotReading(service, account: configuration.account)
    return [enriched(reading, selection: configuration.account)]
}
private func multipleReadings(_ configuration: BothConfiguration, fetch: Bool) async -> [WidgetReading] {
    let selections: [WidgetAccount]
    if let accounts = configuration.accounts {
        var seen = Set<String>()
        selections = accounts.filter { seen.insert($0.id).inserted }
    } else if configuration.codexAccount != nil || configuration.claudeAccount != nil {
        // The old two-service parameters remain decodable for placed widgets.
        selections = [configuration.codexAccount ?? AccountRegistry.defaultProfile(for: .codex).map { WidgetAccount($0, identityHint: nil) },
                      configuration.claudeAccount ?? AccountRegistry.defaultProfile(for: .claude).map { WidgetAccount($0, identityHint: nil) }].compactMap { $0 }
    } else {
        selections = WidgetAccount.make(AccountRegistry.all())
    }
    if selections.isEmpty {
        return QuotaService.allCases.map { service in
            if DemoQuotaData.isEnabled {
                return enriched(WidgetReading(value: .init(service: service, reading: DemoQuotaData.reading(service), needsApp: false), accountLabel: nil, namespace: nil), selection: nil)
            }
            return enriched(snapshotReading(service), selection: nil)
        }
    }
    let readings = await accountReadings(selections, fetch: fetch)
    return configuration.order == .closestToLimit ? ranked(readings) : readings
}
private func hasSavedCredentials(_ store: SharedQuotaStore) -> Bool {
    switch store.service {
    case .codex: return (try? store.load(CodexTokens.self)) != nil
    case .claude: return (try? store.load(ClaudeTokens.self)) != nil
    }
}
func widgetNeedsReconnect(
    explicitlyConfigured: Bool,
    reconnectFailure: Bool,
    hasCredentials: Bool,
    hasReading: Bool
) -> Bool {
    (reconnectFailure && (explicitlyConfigured || hasCredentials || hasReading))
        || (explicitlyConfigured && !hasCredentials)
}
private func loadReading(_ service: QuotaService, account: WidgetAccount? = nil) async -> WidgetReading {
    let resolution = profile(account, for: service)
    guard case let .selected(profile, headerLabel) = resolution else {
        let unavailable = if case .unavailable = resolution { true } else { false }
        return WidgetReading(value: ProviderReading(service: service, reading: nil, needsApp: unavailable), accountLabel: unavailable ? "Choose or reconnect" : nil, namespace: nil)
    }
    if DemoQuotaData.isEnabled {
        return WidgetReading(value: ProviderReading(service: service, reading: DemoQuotaData.reading(service), needsApp: false), accountLabel: headerLabel, namespace: profile.id)
    }
    let store = SharedQuotaStore(service, namespace: profile.id)
    let hasCredentials = hasSavedCredentials(store)
    if account != nil, !hasCredentials {
        return WidgetReading(value: ProviderReading(service: service, reading: nil, needsApp: true), accountLabel: headerLabel, namespace: profile.id)
    }
    do {
        let reading = try await store.fetch(source: "widget", minimumAge: 60)
        return WidgetReading(value: ProviderReading(service: service, reading: reading, needsApp: false), accountLabel: headerLabel, namespace: profile.id)
    } catch {
        let reconnect = (error as? AccessError) == .expired || (error as? AccessError) == .http(401)
            || (error as? ClaudeAccessError)?.requiresReconnect == true
            || SharedQuotaStore.Failure.classify(error) == .renewal
        let savedReading = store.reading()
        let value = ProviderReading(
            service: service,
            reading: savedReading,
            needsApp: widgetNeedsReconnect(
                explicitlyConfigured: account != nil,
                reconnectFailure: reconnect,
                hasCredentials: hasCredentials,
                hasReading: savedReading != nil
            ),
            updateFailed: true
        )
        return WidgetReading(value: value, accountLabel: headerLabel, namespace: profile.id)
    }
}
private func snapshotReading(_ service: QuotaService, account: WidgetAccount? = nil) -> WidgetReading {
    let resolution = profile(account, for: service)
    guard case let .selected(profile, headerLabel) = resolution else {
        let unavailable = if case .unavailable = resolution { true } else { false }
        return WidgetReading(value: ProviderReading(service: service, reading: nil, needsApp: unavailable), accountLabel: unavailable ? "Choose or reconnect" : nil, namespace: nil)
    }
    if DemoQuotaData.isEnabled {
        return WidgetReading(value: ProviderReading(service: service, reading: DemoQuotaData.reading(service), needsApp: false), accountLabel: headerLabel, namespace: profile.id)
    }
    let store = SharedQuotaStore(service, namespace: profile.id)
    let hasCredentials = hasSavedCredentials(store)
    if account != nil, !hasCredentials {
        return WidgetReading(value: ProviderReading(service: service, reading: nil, needsApp: true), accountLabel: headerLabel, namespace: profile.id)
    }
    let savedReading = store.reading()
    let failure = store.failure()
    let value = ProviderReading(
        service: service,
        reading: savedReading,
        needsApp: widgetNeedsReconnect(
            explicitlyConfigured: account != nil,
            reconnectFailure: failure.map { $0 != .temporary } ?? false,
            hasCredentials: hasCredentials,
            hasReading: savedReading != nil
        ),
        updateFailed: failure != nil
    )
    return WidgetReading(value: value, accountLabel: headerLabel, namespace: profile.id)
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
    func placeholder(in context: Context) -> QuotaEntry { entry([enriched(snapshotReading(.codex), selection: nil)]) }
    func snapshot(for configuration: QuotaConfiguration, in context: Context) async -> QuotaEntry {
        entry(await singleReadings(configuration, fetch: false))
    }
    func timeline(for configuration: QuotaConfiguration, in context: Context) async -> Timeline<QuotaEntry> {
        WidgetTimeline.make(await singleReadings(configuration, fetch: true))
    }
}
private enum WidgetTimeline {
    static func make(_ values: [WidgetReading]) -> Timeline<QuotaEntry> { timeline(values) }
}
struct BothConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Accounts"
    @Parameter(title: "Accounts") var accounts: [WidgetAccount]?
    @Parameter(title: "Order", default: .closestToLimit) var order: AccountsWidgetOrder
    static var parameterSummary: some ParameterSummary { Summary { \.$accounts; \.$order } }
    @Parameter(title: "Codex account", optionsProvider: ServiceWidgetAccountOptionsProvider(service: .codex)) var codexAccount: WidgetAccount?
    @Parameter(title: "Claude account", optionsProvider: ServiceWidgetAccountOptionsProvider(service: .claude)) var claudeAccount: WidgetAccount?
}
struct BothProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: .now, values: QuotaService.allCases.map { ProviderReading(service: $0, reading: nil, needsApp: false) }, accountLabels: [:]) }
    func snapshot(for configuration: BothConfiguration, in context: Context) async -> QuotaEntry {
        entry(await multipleReadings(configuration, fetch: false))
    }
    func timeline(for configuration: BothConfiguration, in context: Context) async -> Timeline<QuotaEntry> {
        WidgetTimeline.make(await multipleReadings(configuration, fetch: true))
    }
}
struct SingleLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CodexLockScreen", intent: QuotaConfiguration.self, provider: CodexProvider()) { entry in
            if let account = entry.accounts.first {
                AccountLockView(account: account, date: entry.date, circular: true)
                    .widgetURL(account.url).containerBackground(for: .widget) { Color.clear }
            }
        }
        .configurationDisplayName("Account")
        .description("One account's allowance. Existing Lock Screen widget.")
        .supportedFamilies([.accessoryCircular]).contentMarginsDisabled()
    }
}
struct BothLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "BothLockScreen", intent: BothConfiguration.self, provider: BothProvider()) { entry in
            AccountsLockView(accounts: entry.accounts, date: entry.date).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Accounts")
        .description("Several accounts at a glance. Existing Lock Screen widget.")
        .supportedFamilies([.accessoryRectangular]).contentMarginsDisabled()
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
    @Parameter(title: "Codex account", optionsProvider: ServiceWidgetAccountOptionsProvider(service: .codex)) var codexAccount: WidgetAccount?
    @Parameter(title: "Claude account", optionsProvider: ServiceWidgetAccountOptionsProvider(service: .claude)) var claudeAccount: WidgetAccount?
}
struct CompactProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: .now, values: [.init(service: .codex, reading: nil, needsApp: false), .init(service: .claude, reading: nil, needsApp: false)], accountLabels: [:])
    }
    func snapshot(for configuration: CompactConfiguration, in context: Context) async -> QuotaEntry {
        entry(configuration.services.services.map { service in
            enriched(snapshotReading(service, account: service == .codex ? configuration.codexAccount : configuration.claudeAccount), selection: service == .codex ? configuration.codexAccount : configuration.claudeAccount)
        })
    }
    func timeline(for configuration: CompactConfiguration, in context: Context) async -> Timeline<QuotaEntry> {
        if configuration.services == .both {
            async let codex = loadReading(.codex, account: configuration.codexAccount)
            async let claude = loadReading(.claude, account: configuration.claudeAccount)
            return WidgetTimeline.make(await [enriched(codex, selection: configuration.codexAccount), enriched(claude, selection: configuration.claudeAccount)])
        }
        let service = configuration.services.services[0]
        return WidgetTimeline.make([enriched(await loadReading(service, account: service == .codex ? configuration.codexAccount : configuration.claudeAccount), selection: service == .codex ? configuration.codexAccount : configuration.claudeAccount)])
    }
}
struct CompactLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CompactLockScreen", intent: CompactConfiguration.self, provider: CompactProvider()) { entry in
            AccountsLockView(accounts: entry.accounts, date: entry.date).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Accounts")
        .description("Existing two-service configuration.")
        .supportedFamilies([.accessoryRectangular]).contentMarginsDisabled()
    }
}
#if !WIDGET_UNIT_TESTS
@main
#endif
struct QuotaWidgets: WidgetBundle {
    // Lead with the two complete designs; retain all old kind/intent identities
    // until on-device migration has been validated.
    var body: some Widget { SingleHomeScreenWidget(); BothHomeScreenWidget(); SingleLockScreenWidget(); BothLockScreenWidget(); CompactLockScreenWidget(); ServiceDetailsWidget() }
}
struct ServiceDetailsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ServiceDetails", intent: QuotaConfiguration.self, provider: CodexProvider()) { entry in
            if let account = entry.accounts.first {
                AccountLockView(account: account, date: entry.date).widgetURL(account.url)
                    .containerBackground(for: .widget) { Color.clear }
            }
        }
        .configurationDisplayName("Account")
        .description("One account in depth. Existing Lock Screen widget.")
        .supportedFamilies([.accessoryRectangular]).contentMarginsDisabled()
    }
}
struct HomeEntryView: View {
    let entry: QuotaEntry
    let both: Bool
    var previewFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    var body: some View {
        let displayFamily = previewFamily ?? family
        if displayFamily == .accessoryCircular, let account = entry.accounts.first {
            AccountLockView(account: account, date: entry.date, circular: true)
        } else if displayFamily == .accessoryRectangular {
            if both { AccountsLockView(accounts: entry.accounts, date: entry.date) }
            else if let account = entry.accounts.first { AccountLockView(account: account, date: entry.date) }
        } else {
            HomeQuotaView(values: entry.values, date: entry.date, layout: layout(displayFamily), accounts: entry.accounts)
                .background {
                    // Keep the opaque full-color plate out of the system's
                    // material background pass, while honoring background removal.
                    if renderingMode == .fullColor && showsBackground {
                        HomeWidgetBackground()
                    }
                }
        }
    }
    private func layout(_ family: WidgetFamily) -> HomeQuotaView.Layout {
        if both { return family == .systemSmall ? .accountsSmall : family == .systemLarge ? .large : .dualMedium }
        return family == .systemSmall ? .small : family == .systemLarge ? .accountLarge : .singleMedium
    }
}
struct SingleHomeScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AIQuotaHomeSingle", intent: QuotaConfiguration.self, provider: CodexProvider()) { entry in
            HomeEntryView(entry: entry, both: false)
                .widgetURL(entry.accounts.first?.url)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Account")
        .description("One account in depth, or the account closest to a limit.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}
struct BothHomeScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AIQuotaHomeBoth", intent: BothConfiguration.self, provider: BothProvider()) { entry in
            HomeEntryView(entry: entry, both: true)
                .widgetURL(URL(string: "aiquota-probe://overview"))
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Accounts")
        .description("Choose accounts from any service, ordered by usage or as listed.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}
