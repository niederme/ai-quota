import Foundation

public enum QuotaForecastTextFormatter {
    public static func title(_ forecast: QuotaExhaustionForecast, accountLabel: String) -> String {
        if forecast.scope.provider == "codex", forecast.scope.window == .weekly {
            return "\(accountLabel) • may hit its weekly limit."
        }
        return "\(accountLabel) may hit its \(forecast.scope.window.label) limit"
    }

    public static func detail(_ forecast: QuotaExhaustionForecast,
                              bankedResets: CodexBankedResetContext? = nil,
                              now: Date = .now,
                              calendar: Calendar = .autoupdatingCurrent,
                              locale: Locale = .autoupdatingCurrent) -> String {
        if let count = bankedResets?.availableCount(for: forecast, now: now) {
            let balance = count == 0 ? "You have no banked resets available"
                : "You have \(count.formatted(.number.locale(locale))) banked \(count == 1 ? "reset" : "resets") available"
            return "\(balance) • Resets \(reset(forecast, now: now, calendar: calendar, locale: locale))"
        }
        let basis = forecast.basis == .weeklyPattern
            ? "Based on your usual weekly pattern" : "At your average pace this period"
        return "\(basis) · Resets \(reset(forecast, now: now, calendar: calendar, locale: locale))"
    }

    public static func accessibilitySummary(_ forecast: QuotaExhaustionForecast, accountLabel: String,
                                             bankedResets: CodexBankedResetContext? = nil,
                                             now: Date = .now) -> String {
        let heading = title(forecast, accountLabel: accountLabel).replacingOccurrences(of: " • ", with: ", ")
        let separator = heading.hasSuffix(".") ? " " : ". "
        return heading + separator + detail(forecast, bankedResets: bankedResets, now: now).replacingOccurrences(of: " • ", with: ". ")
    }

    public static func reset(_ forecast: QuotaExhaustionForecast, now: Date = .now,
                             calendar: Calendar = .autoupdatingCurrent,
                             locale: Locale = .autoupdatingCurrent) -> String {
        let dated = forecast.scope.window == .monthly || dayOffset(forecast.scope.resetAt, from: now, calendar: calendar) >= 7
        return forecast.scope.resetAt.formatted(style(dated: dated, calendar: calendar, locale: locale).minute())
    }

    private static func dayOffset(_ date: Date, from now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    private static func style(dated: Bool, calendar: Calendar, locale: Locale) -> Date.FormatStyle {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale,
                                     calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).hour()
        if dated { style = style.month(.abbreviated).day() }
        return style
    }
}
