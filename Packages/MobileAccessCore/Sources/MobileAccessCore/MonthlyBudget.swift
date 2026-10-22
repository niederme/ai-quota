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
        if let code = currencyCode { return value.formatted(.currency(code: code)) }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private var currencyCode: String? {
        guard let code = unit?.uppercased(), code.count == 3,
              code.allSatisfy({ $0 >= "A" && $0 <= "Z" }) else { return nil }
        return code
    }

    public var unitLabel: String {
        switch unit?.lowercased() {
        case "credit", "credits": "credits this month"
        default: currencyCode == nil ? "monthly allowance" : "monthly spend"
        }
    }

    public func confirmedResetDescription(relativeTo date: Date = .now) -> String? {
        guard let resetsAt, resetsAt > date else { return nil }
        return "Monthly resets \(resetsAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
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
