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

    /// Whole currency amounts drop their cents ("$1,000", not "$1,000.00");
    /// fractional ones keep both digits ("$654.50"). Credits show up to two decimals.
    public func amountText(_ value: Double) -> String {
        if let code = currencyCode {
            let digits = value == value.rounded() ? 0 : 2
            return value.formatted(.currency(code: code).precision(.fractionLength(digits)))
        }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// One-line card copy: "434.19 of 7,000 credits" or "$654.98 of $1,000".
    /// The period is left to the reset line ("30d resets Nov 30") under it.
    public var usageText: String {
        isCredits
            ? String(localized: "\(amountText(used)) of \(amountText(limit)) credits", bundle: .module,
                     comment: "Monthly credit budget, such as “434.19 of 7,000 credits”. Values are formatted numbers.")
            : String(localized: "\(amountText(used)) of \(amountText(limit))", bundle: .module,
                     comment: "Monthly spend budget, such as “$654.98 of $1,000”. Values are formatted currency amounts.")
    }

    private var isCredits: Bool {
        switch unit?.lowercased() {
        case "credit", "credits": true
        default: false
        }
    }

    private var currencyCode: String? {
        guard let code = unit?.uppercased(), code.count == 3,
              code.allSatisfy({ $0 >= "A" && $0 <= "Z" }) else { return nil }
        return code
    }

    public var unitLabel: String {
        switch unit?.lowercased() {
        case "credit", "credits": String(localized: "credits this month", bundle: .module, comment: "Follows an amount, as in “434 of 7,000 credits this month used”.")
        default: currencyCode == nil
            ? String(localized: "monthly allowance", bundle: .module, comment: "Follows an amount, as in “40 of 100 monthly allowance used”.")
            : String(localized: "monthly spend", bundle: .module, comment: "Follows an amount, as in “$654 of $1,000 monthly spend used”.")
        }
    }

    /// Budgets run for a calendar month, so the key is that month's length
    /// ("28d", "30d", "31d"), anchored to the reading like the Mac's CalendarMonthLabel.
    public static func periodDays(containing readingAt: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.range(of: .day, in: .month, for: readingAt)?.count ?? 30
    }

    public static func periodLabel(containing readingAt: Date) -> String {
        WindowKeyText.days(periodDays(containing: readingAt))
    }

    public func confirmedResetDescription(readingAt: Date, relativeTo date: Date = .now) -> String? {
        guard let resetsAt, resetsAt > date else { return nil }
        return Self.resets(Self.periodLabel(containing: readingAt), resetsAt)
    }

    private static func resets(_ period: String, _ resetsAt: Date) -> String {
        String(localized: "\(period) resets \(resetsAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))", bundle: .module,
               comment: "Budget reset caption. First value is a window key such as “30d”, second a date and time.")
    }

    public func resetDescription(readingAt: Date, relativeTo date: Date = .now) -> String {
        let period = Self.periodLabel(containing: readingAt)
        guard let resetsAt else {
            return String(localized: "\(period) reset unavailable", bundle: .module,
                          comment: "Shown when a usage window has no reset time. The value is a window key such as “30d”.")
        }
        guard resetsAt > date else {
            return String(localized: "\(period) reset awaiting confirmation", bundle: .module,
                          comment: "Shown when a usage window's reset time has passed but no fresh reading has arrived. The value is a window key such as “30d”.")
        }
        return Self.resets(period, resetsAt)
    }

    public var accessibilitySummary: String {
        String(localized: "Monthly: \(amountText(used)) of \(amountText(limit)) \(unitLabel) used", bundle: .module,
               comment: "VoiceOver. First two values are amounts, third a phrase such as “credits this month” or “monthly spend”.")
    }
}
