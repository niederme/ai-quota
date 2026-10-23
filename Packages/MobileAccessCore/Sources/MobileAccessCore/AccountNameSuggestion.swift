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
        let used = Set(existingLabels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        if !used.contains(stem.lowercased()) { return stem }
        var number = 2
        while used.contains("\(stem) \(number)".lowercased()) { number += 1 }
        return "\(stem) \(number)"
    }
}
