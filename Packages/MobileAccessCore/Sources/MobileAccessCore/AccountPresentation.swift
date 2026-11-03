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
    public let service: String
    public let plan: String?
    public let title: String
    public let subtitle: String
    public let requiresName: Bool
    /// Notifications omit aliases (which may contain private names or emails).
    public let notificationTitle: String
    public var managementHint: String? { requiresName ? "Give matching connections distinct names in Settings" : nil }

    public static func resolve(_ identity: AccountIdentity, among peers: [AccountIdentity]) -> Self {
        let base = components(identity)
        let matching = peers.filter { $0.key != identity.key && fold(components($0).title) == fold(base.title) }
        let privateMatching = peers.filter { $0.key != identity.key && fold(components($0).notificationTitle) == fold(base.notificationTitle) }
        return Self(service: base.service, plan: base.plan, title: base.title, subtitle: base.subtitle, requiresName: !matching.isEmpty,
                    notificationTitle: privateMatching.isEmpty ? base.notificationTitle : "\(identity.service) usage update")
    }

    private static func components(_ i: AccountIdentity) -> Self {
        let service = clean(i.service)
        let label = clean(i.label)
        let plan = normalizedPlan(i.plan)
        let stem = plan.map { "\(service) \($0)" } ?? service
        let generated = label.isEmpty || fold(label) == fold(service) || fold(label) == "live" || UUID(uuidString: label) != nil
            || (i.origin == .generated && fold(label) == "personal")
            || label.range(of: "^(?:(?:codex|claude)\\s+)?(?:account|service)\\s*[0-9]+$", options: [.regularExpression, .caseInsensitive]) != nil
            || (i.origin == .generated && isGeneratedPlanLabel(label, service: service))
        // Unknown non-default legacy names are retained; only proven default patterns
        // are suppressed. An explicit rename always wins, including “Account 2”.
        let alias = i.origin == .user ? (label.isEmpty ? nil : label) : (generated ? nil : label)
        let title: String
        if let alias, fold(alias) != fold(stem), fold(alias) != fold(service) {
            title = plan == nil && alias.lowercased().hasPrefix(service.lowercased() + " ") ? alias : "\(stem) · \(alias)"
        } else { title = stem }
        let subtitle = [plan.map { "\($0) plan" } ?? "Plan unavailable", alias.flatMap { fold($0) == fold(stem) || fold($0) == fold(service) ? nil : $0 }].compactMap { $0 }.joined(separator: " · ")
        return Self(service: service, plan: plan, title: title, subtitle: subtitle, requiresName: false, notificationTitle: stem)
    }
    private static func clean(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    private static func fold(_ s: String) -> String { clean(s).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
    private static func normalizedPlan(_ p: String?) -> String? {
        guard let raw = p else { return nil }
        let p = clean(raw)
        guard !p.isEmpty, !["unknown", "not reported", "n/a"].contains(fold(p)) else { return nil }
        return fold(p) == "prolite" ? "Pro" : p.capitalized
    }
    private static func isGeneratedPlanLabel(_ label: String, service: String) -> Bool {
        let prefix = service + " "
        guard label.lowercased().hasPrefix(prefix.lowercased()) else { return false }
        let tail = String(label.dropFirst(prefix.count)).lowercased()
        return tail.range(of: "^(?:pro|prolite|business|enterprise|max|team|teams|free|plus|demo)(?: [0-9]+)?$", options: .regularExpression) != nil
    }
}
