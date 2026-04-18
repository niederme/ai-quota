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
            return "today \(time)"
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(resetAt, inSameDayAs: tomorrow) {
            return "tomorrow \(time)"
        }

        return "\(weekdayText(for: resetAt, locale: locale)) \(time)"
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

    private static func weekdayText(for date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter.string(from: date)
    }
}
