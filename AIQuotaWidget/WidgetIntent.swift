import AppIntents
import WidgetKit
import AIQuotaKit

// MARK: - Refresh intent

struct RefreshWidgetIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Refresh Widget"
    nonisolated(unsafe) static var description = IntentDescription("Refresh AI quota data.")
    nonisolated(unsafe) static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        let refreshService = WidgetRefreshService()
        _ = await refreshService.refreshAvailableServices(force: true)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Configurable account selection

struct WidgetAccount: AppEntity {
    nonisolated(unsafe) static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Account")
    nonisolated(unsafe) static var defaultQuery = WidgetAccountQuery()

    let id: String
    let name: String
    let provider: ServiceType

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(provider == .codex ? "Codex" : "Claude Code") · \(name)")
    }

    init(_ account: ConnectedAccount) {
        id = account.id
        name = account.displayLabel
        provider = account.provider
    }
}

struct WidgetAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetAccount] {
        identifiers.compactMap { AccountRegistry.account(id: $0).map(WidgetAccount.init) }
    }

    func suggestedEntities() async throws -> [WidgetAccount] {
        AccountRegistry.orderedAccounts().map(WidgetAccount.init)
    }
}

// Keep the service choice for installed widgets that predate account support.

enum ServiceOption: String, AppEnum {
    case codex
    case claude

    nonisolated(unsafe) static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Service")
    nonisolated(unsafe) static var caseDisplayRepresentations: [ServiceOption: DisplayRepresentation] = [
        .codex:  .init(title: "Codex"),
        .claude: .init(title: "Claude Code"),
    ]
}

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource       = "Service"
    nonisolated(unsafe) static var description = IntentDescription("Choose which AI service to display.")

    @Parameter(title: "Service", default: ServiceOption.codex)
    var service: ServiceOption

    @Parameter(title: "Account")
    var account: WidgetAccount?
}

struct MediumConfigurationAppIntent: WidgetConfigurationIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "AIQuota"
    nonisolated(unsafe) static var description = IntentDescription("Shows both Codex and Claude Code usage.")
}
