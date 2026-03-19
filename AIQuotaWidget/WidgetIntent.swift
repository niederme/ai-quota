import AppIntents
import WidgetKit

// MARK: - Refresh intent

struct RefreshWidgetIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Refresh Widget"
    nonisolated(unsafe) static var description = IntentDescription("Refresh AI quota data.")
    nonisolated(unsafe) static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Configurable service selection

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
}
