import Foundation

/// A provider-reported monthly allowance. Amounts retain the provider's units.
public struct MonthlyBudget: Codable, Sendable, Equatable {
    public let used: Double
    public let limit: Double
    public let unit: String?
    public let resetsAt: Date?

    public init?(used: Double?, limit: Double?, unit: String?, resetsAt: Date? = nil) {
        guard let used, let limit, used.isFinite, used >= 0,
              limit.isFinite, limit > 0 else { return nil }
        self.used = used
        self.limit = limit
        self.unit = unit
        self.resetsAt = resetsAt
    }

    public var usedPercent: Double { min(100, max(0, used / limit * 100)) }

    public func amountText(_ value: Double) -> String {
        if unit?.uppercased() == "USD" { return value.formatted(.currency(code: "USD")) }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    public var unitLabel: String {
        switch unit?.lowercased() {
        case "credit", "credits": "credits this month"
        case "usd": "monthly spend"
        default: "monthly allowance"
        }
    }

    public func resetDescription(relativeTo date: Date = .now) -> String {
        guard let resetsAt else { return "Monthly reset unavailable" }
        guard resetsAt > date else { return "Monthly reset unconfirmed" }
        return "Monthly resets \(resetsAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
    }

    public var accessibilitySummary: String {
        "Monthly: \(amountText(used)) of \(amountText(limit)) \(unitLabel) used"
    }
}
