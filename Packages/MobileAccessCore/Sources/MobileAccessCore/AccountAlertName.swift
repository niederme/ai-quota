import Foundation

/// Presentation only: never use an alert name as an account or dismissal key.
public enum AccountAlertName {
    public static func make(service: String, label: String, explicitlyNamed: Bool = false) -> String {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = label.split(whereSeparator: \.isWhitespace)
        let ordinal = parts.count == 2
            && ["account", "service"].contains(parts[0].lowercased())
            && parts[1].allSatisfy(\.isNumber)
        guard !label.isEmpty, explicitlyNamed || !ordinal else { return service }
        if label.localizedCaseInsensitiveContains(service) { return label }
        return "\(service) · \(label)"
    }
}
