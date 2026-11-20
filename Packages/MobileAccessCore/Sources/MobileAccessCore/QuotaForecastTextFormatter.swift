import Foundation

public enum QuotaForecastTextFormatter {
    public static func title(_ forecast: QuotaExhaustionForecast, accountLabel: String) -> String {
        String(localized: "\(accountLabel) is overpacing the \(windowLabel(forecast)) limit", bundle: .module,
               comment: "Forecast title. First value is the account name, second a window key such as “5h”, “7d”, “30d” or the word “monthly”.")
    }

    public static func sentence(_ forecast: QuotaExhaustionForecast) -> String {
        String(localized: "You’re on pace to hit your \(windowLabel(forecast)) limit early", bundle: .module,
               comment: "Forecast sentence. The value is a window key such as “5h”, “7d”, “30d” or the word “monthly”.")
    }

    private static func windowLabel(_ forecast: QuotaExhaustionForecast) -> String {
        let window: String
        switch forecast.scope.window {
        case .fiveHour: window = WindowKeyText.hours(5)
        case .weekly: window = WindowKeyText.days(7)
        case .monthly:
            // Only name an exact day count when the provider supplied it.
            if let duration = forecast.windowDuration, (28 * 86400...31 * 86400).contains(duration),
               duration.truncatingRemainder(dividingBy: 86400) == 0 {
                window = WindowKeyText.days(Int(duration / 86400))
            } else {
                window = String(localized: "monthly", bundle: .module, comment: "Used inside “overpacing the monthly limit”.")
            }
        }
        return window
    }

    public static func detail(_ forecast: QuotaExhaustionForecast,
                              bankedResets: CodexBankedResetContext? = nil,
                              now: Date = .now,
                              calendar: Calendar = .autoupdatingCurrent,
                              locale: Locale = .autoupdatingCurrent) -> String {
        if let count = bankedResets?.availableCount(for: forecast, now: now) {
            let balance = String(localized: "\(count) resets available", bundle: .module, locale: locale,
                                 comment: "Number of banked Codex resets the user can still use. Needs plural forms.")
            return resetsLine(reset(forecast, now: now, calendar: calendar, locale: locale), balance, locale: locale)
        }
        let basis = forecast.basis == .weeklyPattern
            ? String(localized: "Based on your usual weekly pattern", bundle: .module, locale: locale, comment: "Forecast basis.")
            : String(localized: "At your average pace this period", bundle: .module, locale: locale, comment: "Forecast basis.")
        return resetsLine(reset(forecast, now: now, calendar: calendar, locale: locale), basis, locale: locale)
    }

    private static func resetsLine(_ when: String, _ detail: String, locale: Locale) -> String {
        String(localized: "Resets \(when) • \(detail)", bundle: .module, locale: locale,
               comment: "Forecast detail line. First value is a day and time, second a short explanation. Keep the “ • ” separator.")
    }

    public static func accessibilitySummary(_ forecast: QuotaExhaustionForecast, accountLabel: String,
                                             bankedResets: CodexBankedResetContext? = nil,
                                             now: Date = .now) -> String {
        let heading = title(forecast, accountLabel: accountLabel)
        let separator = heading.hasSuffix(".") ? " " : ". "
        return heading + separator + detail(forecast, bankedResets: bankedResets, now: now).replacingOccurrences(of: " • ", with: ". ")
    }

    public static func reset(_ forecast: QuotaExhaustionForecast, now: Date = .now,
                             calendar: Calendar = .autoupdatingCurrent,
                             locale: Locale = .autoupdatingCurrent) -> String {
        let dated = forecast.scope.window == .monthly || dayOffset(forecast.scope.resetAt, from: now, calendar: calendar) >= 7
        // Format each component with the user's locale, without a date/time connector.
        let date = forecast.scope.resetAt.formatted(style(dated: dated, calendar: calendar, locale: locale))
        let time = forecast.scope.resetAt.formatted(Date.FormatStyle(date: .omitted, time: .omitted,
            locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute())
        return "\(date) \(time)"
    }

    private static func dayOffset(_ date: Date, from now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    private static func style(dated: Bool, calendar: Calendar, locale: Locale) -> Date.FormatStyle {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale,
                                     calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)
        if dated { style = style.month(.abbreviated).day() }
        return style
    }
}
