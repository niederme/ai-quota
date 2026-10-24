import Foundation

/// A compact calendar-month label, not a measured billing-window duration.
/// Anchor it to the reading, so a cached reading keeps its original month.
public enum CalendarMonthLabel {
    /// Use Gregorian UTC consistently across locale and timezone changes.
    /// This is display context; it supplies no billing-period or reset metadata.
    public static var reportingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    public static func compact(containing readingAt: Date, calendar: Calendar = reportingCalendar) -> String {
        guard let days = dayCount(containing: readingAt, calendar: calendar) else { return "Month" }
        return "\(days)d"
    }

    public static func spoken(containing readingAt: Date, calendar: Calendar = reportingCalendar) -> String {
        guard let days = dayCount(containing: readingAt, calendar: calendar) else { return "calendar month" }
        return "\(days) day calendar month"
    }

    private static func dayCount(containing date: Date, calendar: Calendar) -> Int? {
        // Calendar ranges preserve leap days and ignore DST's 23/25-hour days.
        calendar.range(of: .day, in: .month, for: date)?.count
    }
}
