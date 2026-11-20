import Foundation
import MobileAccessCore

public enum ResetTimeTextFormatter {
    /// Shown once in place of one caption per window when every window's reset
    /// time has passed without a fresh reading (for example a full Codex reset).
    public static var combinedAwaitingCaption: String {
        String(localized: "Reset awaiting confirmation", bundle: .module,
               comment: "Shown once when every usage window's reset time has passed but no fresh reading has arrived yet.")
    }

    public static func allAwaitingConfirmation(_ resets: [Date?], now: Date = .now) -> Bool {
        resets.count > 1 && resets.allSatisfy { reset in
            guard let reset, reset != .distantFuture, reset != .distantPast else { return false }
            return reset <= now
        }
    }

    public static func windowCaption(
        _ windowLabel: String,
        resetAt: Date?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let windowLabel = WindowKeyText.display(windowLabel)
        guard let resetAt = upcoming(resetAt, now: now) else {
            return fallbackCaption(windowLabel, resetAt: resetAt, locale: locale)
        }
        let time = timeText(for: resetAt, locale: locale)
        if calendar.isDate(resetAt, inSameDayAs: now) {
            return String(localized: "\(windowLabel) resets Today \(time)", bundle: .module, locale: locale,
                          comment: "Reset caption. First value is a usage window key such as “5h”, second a time such as “8:29pm”.")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(resetAt, inSameDayAs: tomorrow) {
            return String(localized: "\(windowLabel) resets Tomorrow \(time)", bundle: .module, locale: locale,
                          comment: "Reset caption. First value is a usage window key such as “5h”, second a time such as “12:15am”.")
        }
        return resets(windowLabel, dayAndTime(for: resetAt, now: now, calendar: calendar, locale: locale), locale: locale)
    }

    public static func compactWindowCaption(
        _ windowLabel: String,
        resetAt: Date?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let windowLabel = WindowKeyText.display(windowLabel)
        guard let resetAt = upcoming(resetAt, now: now) else {
            return fallbackCaption(windowLabel, resetAt: resetAt, locale: locale)
        }
        let phrase = calendar.isDate(resetAt, inSameDayAs: now)
            ? timeText(for: resetAt, locale: locale)
            : dayAndTime(for: resetAt, now: now, calendar: calendar, locale: locale)
        return resets(windowLabel, phrase, locale: locale)
    }

    /// "resets 3:00pm" with no window key, for a gauge that already names its window.
    public static func compactResetCaption(
        resetAt: Date,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let phrase = calendar.isDate(resetAt, inSameDayAs: now)
            ? timeText(for: resetAt, locale: locale)
            : dayAndTime(for: resetAt, now: now, calendar: calendar, locale: locale)
        return String(localized: "resets \(phrase)", bundle: .module, locale: locale,
                      comment: "Reset caption under a budget gauge. The value is a time or a day and time, such as “Wed. 1:03pm”.")
    }

    private static func resets(_ label: String, _ when: String, locale: Locale) -> String {
        String(localized: "\(label) resets \(when)", bundle: .module, locale: locale,
               comment: "Reset caption. First value is a usage window key such as “7d”, second a day and time such as “Wed. 1:03pm”.")
    }

    private static func upcoming(_ resetAt: Date?, now: Date) -> Date? {
        guard let resetAt, resetAt != .distantFuture, resetAt != .distantPast, resetAt > now else { return nil }
        return resetAt
    }

    private static func fallbackCaption(_ label: String, resetAt: Date?, locale: Locale) -> String {
        guard let resetAt, resetAt != .distantFuture, resetAt != .distantPast else {
            return String(localized: "\(label) reset unavailable", bundle: .module, locale: locale,
                          comment: "Shown when a usage window has no reset time. The value is a window key such as “5h”.")
        }
        return String(localized: "\(label) reset awaiting confirmation", bundle: .module, locale: locale,
                      comment: "Shown when a usage window's reset time has passed but no fresh reading has arrived. The value is a window key such as “7d”.")
    }

    private static func isEnglish(_ locale: Locale) -> Bool {
        locale.language.languageCode == .english
    }

    /// English keeps the house style ("Wed. 1:03pm", "Mon. Sep 21 2:27pm"); other
    /// languages use the locale's own weekday, date order and 12/24-hour clock.
    private static func dayAndTime(for date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        guard isEnglish(locale) else {
            return formatted(date, template: days >= 7 ? "EEEMMMdjmm" : "EEEjmm", calendar: calendar, locale: locale)
        }
        let weekday = weekdayAbbrev(for: date, calendar: calendar)
        let time = timeText(for: date, locale: locale)
        guard days >= 7 else { return "\(weekday) \(time)" }
        return "\(weekday) \(formatted(date, template: "MMM d", calendar: calendar, locale: locale)) \(time)"
    }

    private static func formatted(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private static func timeText(for date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        let text = formatter.string(from: date)
        // English squeezes "8:29 PM" to "8:29pm"; other languages keep their own clock text.
        guard isEnglish(locale) else { return text }
        return text.components(separatedBy: .whitespacesAndNewlines).joined().lowercased()
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
