import Foundation

/// A starting name for a new connection. The account owner can always edit it.
public enum AccountNameSuggestion {
    public static func make(service: String, plan: String?, existingLabels: [String]) -> String {
        let plan = plan?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stem: String
        if let plan, !plan.isEmpty, plan.caseInsensitiveCompare("Unknown") != .orderedSame {
            stem = "\(service) \(plan)"
        } else {
            stem = service
        }
        // Matching plans need an owner-chosen alias, not a generated ordinal.
        return stem
    }
}
