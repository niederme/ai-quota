import Testing
@testable import MobileAccessCore

@Test func accountNamesUsePlansAndLeaveCollisionsForExplicitNaming() {
    #expect(AccountNameSuggestion.make(service: "Claude", plan: "Enterprise", existingLabels: []) == "Claude Enterprise")
    #expect(AccountNameSuggestion.make(service: "Claude", plan: "Pro", existingLabels: ["Claude Enterprise"]) == "Claude Pro")
    #expect(AccountNameSuggestion.make(service: "Claude", plan: "Enterprise",
                                       existingLabels: ["claude enterprise", "Claude Enterprise 2"]) == "Claude Enterprise")
    #expect(AccountNameSuggestion.make(service: "Codex", plan: nil, existingLabels: ["Codex"]) == "Codex")
    #expect(AccountNameSuggestion.make(service: "Claude", plan: "Unknown", existingLabels: []) == "Claude")
}
