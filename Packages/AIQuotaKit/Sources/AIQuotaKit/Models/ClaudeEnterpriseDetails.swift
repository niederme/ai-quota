import Foundation
import MobileAccessCore

public struct ClaudeEnterprisePeriod: Sendable, Equatable {
    public let startDate: Date
    public let endDate: Date
    public let reportingTimeZone: TimeZone

    public init(startDate: Date, endDate: Date, reportingTimeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) {
        self.startDate = startDate
        self.endDate = endDate
        self.reportingTimeZone = reportingTimeZone
    }

    public var apiStartDate: String { Self.dateString(startDate, in: reportingTimeZone) }
    public var apiEndDate: String { Self.dateString(endDate, in: reportingTimeZone) }
    public var rangeLabel: String? {
        ClaudeEnterpriseDateOnly.displayRange(startDate: apiStartDate, endDate: apiEndDate)
    }

    public static func currentMonth(
        at date: Date = .now,
        calendar: Calendar? = nil
    ) -> ClaudeEnterprisePeriod {
        var reportingCalendar = calendar ?? Calendar(identifier: .gregorian)
        if calendar == nil { reportingCalendar.timeZone = .current }
        let start = reportingCalendar.dateInterval(of: .month, for: date)?.start
            ?? reportingCalendar.startOfDay(for: date)
        return ClaudeEnterprisePeriod(startDate: start, endDate: date,
                                      reportingTimeZone: reportingCalendar.timeZone)
    }

    private static func dateString(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

public struct ScopedClaudeEnterpriseSpend: Sendable, Equatable {
    public let report: ClaudeSpendHistory
    public let scopeID: String
    public let period: ClaudeEnterprisePeriod
    public let fetchedAt: Date

    public init(
        report: ClaudeSpendHistory,
        scopeID: String,
        period: ClaudeEnterprisePeriod,
        fetchedAt: Date = .now
    ) {
        self.report = report
        self.scopeID = scopeID
        self.period = period
        self.fetchedAt = fetchedAt
    }
}

public struct ScopedClaudeEnterpriseSkills: Sendable, Equatable {
    public let report: ClaudeEnterpriseSkillsResponse
    public let scopeID: String
    public let period: ClaudeEnterprisePeriod
    public let fetchedAt: Date

    public init(
        report: ClaudeEnterpriseSkillsResponse,
        scopeID: String,
        period: ClaudeEnterprisePeriod,
        fetchedAt: Date = .now
    ) {
        self.report = report
        self.scopeID = scopeID
        self.period = period
        self.fetchedAt = fetchedAt
    }
}

public struct ClaudeEnterpriseReconnectPromptPolicy: Sendable, Equatable {
    public private(set) var isPresented = false
    public private(set) var wasDismissed = false

    public init() {}

    public mutating func beginDetailPresentation() {
        isPresented = false
        wasDismissed = false
    }

    @discardableResult
    public mutating func offer() -> Bool {
        guard !isPresented, !wasDismissed else { return false }
        isPresented = true
        return true
    }

    public mutating func dismiss() {
        isPresented = false
        wasDismissed = true
    }

    public mutating func reset() {
        self = Self()
    }
}
