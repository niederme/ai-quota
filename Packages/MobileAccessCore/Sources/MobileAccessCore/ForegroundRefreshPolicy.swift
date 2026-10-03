import Foundation

public struct ForegroundRefreshPolicy: Sendable {
    private static let recentReadingAge: TimeInterval = 30
    private static let automaticAttemptInterval: TimeInterval = 15

    private var lastAutomaticAttempt: Date?

    public init() {}

    public mutating func beginAutomatic(at date: Date, reading: QuotaReading?) -> Bool {
        if let reading, !WidgetFreshness.isOld(reading, at: date) {
            let age = date.timeIntervalSince(reading.fetchedAt)
            if age >= 0, age < Self.recentReadingAge { return false }
        }

        if let lastAutomaticAttempt {
            let age = date.timeIntervalSince(lastAutomaticAttempt)
            if age >= 0, age < Self.automaticAttemptInterval { return false }
        }

        lastAutomaticAttempt = date
        return true
    }

    public mutating func reset() {
        lastAutomaticAttempt = nil
    }
}
