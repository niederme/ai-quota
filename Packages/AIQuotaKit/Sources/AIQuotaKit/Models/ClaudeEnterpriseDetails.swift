import Foundation
import MobileAccessCore

public struct ClaudeEnterprisePeriod: Sendable, Equatable {
    public let startDate: Date
    public let endDate: Date

    public init(startDate: Date, endDate: Date) {
        self.startDate = startDate
        self.endDate = endDate
    }

    public static func currentMonth(
        at date: Date = .now,
        calendar: Calendar? = nil
    ) -> ClaudeEnterprisePeriod {
        var reportingCalendar = calendar ?? Calendar(identifier: .gregorian)
        if calendar == nil { reportingCalendar.timeZone = TimeZone(secondsFromGMT: 0)! }
        let start = reportingCalendar.dateInterval(of: .month, for: date)?.start
            ?? reportingCalendar.startOfDay(for: date)
        return ClaudeEnterprisePeriod(startDate: start, endDate: date)
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
