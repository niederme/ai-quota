import Foundation

public enum ResetTimeTextFormatter {
    public static func windowCaption(
        _ windowLabel: String,
        resetAt: Date?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        "\(windowLabel) resets \(resetPhrase(resetAt: resetAt, now: now, calendar: calendar, locale: locale))"
    }

    public static func compactWindowCaption(
        _ windowLabel: String,
        resetAt: Date?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        "\(windowLabel) resets \(compactResetPhrase(resetAt: resetAt, now: now, calendar: calendar, locale: locale))"
    }

    private static func resetPhrase(
        resetAt: Date?,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        guard let resetAt, resetAt != .distantFuture, resetAt != .distantPast else {
            return "soon"
        }

        if resetAt <= now {
            return "now"
        }

        let time = timeText(for: resetAt, locale: locale)
        if calendar.isDate(resetAt, inSameDayAs: now) {
            return "Today \(time)"
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(resetAt, inSameDayAs: tomorrow) {
            return "Tomorrow \(time)"
        }

        return "\(weekdayAbbrev(for: resetAt, calendar: calendar)) \(time)"
    }

    private static func compactResetPhrase(
        resetAt: Date?,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        guard let resetAt, resetAt != .distantFuture, resetAt != .distantPast else {
            return "soon"
        }

        if resetAt <= now {
            return "now"
        }

        let time = timeText(for: resetAt, locale: locale)
        if calendar.isDate(resetAt, inSameDayAs: now) {
            return time
        }

        return "\(weekdayAbbrev(for: resetAt, calendar: calendar)) \(time)"
    }

    private static func timeText(for date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("j:mm")

        return formatter.string(from: date)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .lowercased()
    }

    private static func weekdayAbbrev(for date: Date, calendar: Calendar) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: return "Sun."
        case 2: return "Mon."
        case 3: return "Tues."
        case 4: return "Wed."
        case 5: return "Thurs."
        case 6: return "Fri."
        case 7: return "Sat."
        default: return ""
        }
    }
}
