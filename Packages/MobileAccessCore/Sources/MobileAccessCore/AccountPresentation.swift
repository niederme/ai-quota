import Foundation

/// Only human-facing metadata enters this policy. Opaque IDs are matching keys,
/// never display names. Naming never changes account selection or storage keys.
public struct AccountIdentity: Equatable, Sendable {
    public enum Origin: String, Codable, Sendable { case generated, user, unknown }
    public let key: String
    public let service: String
    public let label: String
    public let plan: String?
    public let origin: Origin
    public init(key: String, service: String, label: String, plan: String?, origin: Origin = .unknown) {
        self.key = key; self.service = service; self.label = label; self.plan = plan; self.origin = origin
    }
}

public struct AccountPresentation: Equatable, Sendable {
    public enum HeadingStyle { case service, fullIdentity }
    public let service: String
    public let plan: String?
    public let alias: String?
    public let title: String
    public let subtitle: String
    public let requiresName: Bool
    /// Notifications omit aliases (which may contain private names or emails).
    public let notificationTitle: String
    public var managementHint: String? { requiresName ? "Give matching connections distinct names in Settings" : nil }

    /// Split cards need plan/alias below the service. A full identity already
    /// includes both; keep only metadata that adds information beneath it.
    public func subtitle(for heading: HeadingStyle) -> String? {
        switch heading {
        case .service: return subtitle
        case .fullIdentity: return plan == nil ? "Plan unavailable" : nil
        }
    }

    public static func resolve(_ identity: AccountIdentity, among peers: [AccountIdentity]) -> Self {
        let base = components(identity)
        let matching = peers.filter { $0.key != identity.key && fold(components($0).title) == fold(base.title) }
        let privateMatching = peers.filter { $0.key != identity.key && fold(components($0).notificationTitle) == fold(base.notificationTitle) }
        return Self(service: base.service, plan: base.plan, alias: base.alias, title: base.title, subtitle: base.subtitle, requiresName: !matching.isEmpty,
                    notificationTitle: privateMatching.isEmpty ? base.notificationTitle : "\(identity.service) usage update")
    }

    private static func components(_ i: AccountIdentity) -> Self {
        let service = clean(i.service)
        let label = clean(i.label)
        let plan = normalizedPlan(i.plan)
        let stem = plan.map { "\(service) \($0)" } ?? service
        let generated = i.origin == .generated || label.isEmpty || fold(label) == fold(service) || fold(label) == "live" || UUID(uuidString: label) != nil
            || label.range(of: "^(?:(?:codex|claude)\\s+)?(?:account|service)\\s*[0-9]+$", options: [.regularExpression, .caseInsensitive]) != nil
        // Unknown non-default legacy names are retained; only proven default patterns
        // are suppressed. An explicit rename always wins, including “Account 2”.
        let alias = i.origin == .user ? (label.isEmpty ? nil : label) : (generated ? nil : label)
        // A name that already starts with the service and plan ("Claude Max • Personal")
        // only adds what follows it; the heading supplies "Claude Max" once.
        let shown = alias.map { plan == nil ? $0 : removingPrefix(stem, from: $0) }
        let title: String
        if let shown, fold(shown) != fold(stem), fold(shown) != fold(service) {
            title = plan == nil && shown.lowercased().hasPrefix(service.lowercased() + " ") ? shown : "\(stem) · \(shown)"
        } else { title = stem }
        let subtitle = [plan.map { "\($0) plan" } ?? "Plan unavailable", shown.flatMap { fold($0) == fold(stem) || fold($0) == fold(service) ? nil : $0 }].compactMap { $0 }.joined(separator: " · ")
        return Self(service: service, plan: plan, alias: alias, title: title, subtitle: subtitle, requiresName: false, notificationTitle: stem)
    }
    /// The part of `name` after a leading `prefix` and any separator, or `name`
    /// itself when it doesn't start with `prefix` as whole words.
    private static func removingPrefix(_ prefix: String, from name: String) -> String {
        guard let range = name.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) else { return name }
        let rest = name[range.upperBound...]
        guard let next = rest.first else { return prefix }
        let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "·•-–—:|/,()"))
        guard next.unicodeScalars.allSatisfy({ separators.contains($0) }) else { return name }
        let trimmed = rest.trimmingCharacters(in: separators)
        return trimmed.isEmpty ? prefix : clean(trimmed)
    }
    private static func clean(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    private static func fold(_ s: String) -> String { clean(s).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
    private static func normalizedPlan(_ p: String?) -> String? {
        guard let raw = p else { return nil }
        let p = clean(raw)
        guard !p.isEmpty, !["unknown", "not reported", "n/a"].contains(fold(p)) else { return nil }
        return fold(p) == "prolite" ? "Pro" : p.capitalized
    }
}
