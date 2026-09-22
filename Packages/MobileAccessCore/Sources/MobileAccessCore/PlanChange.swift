import Foundation

/// A transition between known plan labels; first sign-in and missing metadata are not changes.
public struct PlanChange: Equatable, Sendable {
    public let previous: String
    public let current: String

    public init?(previous: String?, current: String?) {
        func normalize(_ value: String?) -> String? {
            guard let value else { return nil }
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !["", "unknown", "not reported", "n/a"].contains(key) else { return nil }
            return key == "prolite" ? "pro" : key
        }
        guard let old = normalize(previous), let new = normalize(current), old != new else { return nil }
        self.previous = old.capitalized
        self.current = new.capitalized
    }
}
