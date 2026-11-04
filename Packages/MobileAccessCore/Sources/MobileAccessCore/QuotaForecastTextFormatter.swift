import Foundation

public enum QuotaForecastTextFormatter {
    public static func title(_ forecast: QuotaExhaustionForecast, accountLabel: String) -> String {
        "\(accountLabel) is overpacing the \(windowLabel(forecast)) limit."
    }

    public static func sentence(_ forecast: QuotaExhaustionForecast) -> String {
        "You’re on pace to hit your \(windowLabel(forecast)) limit early"
    }

    private static func windowLabel(_ forecast: QuotaExhaustionForecast) -> String {
        let window: String
        switch forecast.scope.window {
        case .fiveHour: window = "5h"
        case .weekly: window = "7d"
        case .monthly:
            // Only name an exact day count when the provider supplied it.
            if let duration = forecast.windowDuration, (28 * 86400...31 * 86400).contains(duration),
               duration.truncatingRemainder(dividingBy: 86400) == 0 {
                window = "\(Int(duration / 86400))d"
            } else {
                window = "monthly"
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
            let balance = "\(count.formatted(.number.locale(locale))) banked \(count == 1 ? "reset" : "resets") available"
            return "Resets \(reset(forecast, now: now, calendar: calendar, locale: locale)) • \(balance)"
        }
        let basis = forecast.basis == .weeklyPattern
            ? "Based on your usual weekly pattern" : "At your average pace this period"
        return "Resets \(reset(forecast, now: now, calendar: calendar, locale: locale)) • \(basis)"
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
