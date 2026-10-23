import Testing
@testable import MobileAccessCore

@Test func accountNamesUseKnownPlansAndNumberDuplicates() {
    #expect(AccountNameSuggestion.make(service: "Claude", plan: "Enterprise", existingLabels: []) == "Claude Enterprise")
    #expect(AccountNameSuggestion.make(service: "Claude", plan: "Pro", existingLabels: ["Claude Enterprise"]) == "Claude Pro")
    #expect(AccountNameSuggestion.make(service: "Claude", plan: "Enterprise",
                                       existingLabels: ["claude enterprise", "Claude Enterprise 2"]) == "Claude Enterprise 3")
    #expect(AccountNameSuggestion.make(service: "Codex", plan: nil, existingLabels: ["Codex"]) == "Codex 2")
    #expect(AccountNameSuggestion.make(service: "Claude", plan: "Unknown", existingLabels: []) == "Claude")
}
