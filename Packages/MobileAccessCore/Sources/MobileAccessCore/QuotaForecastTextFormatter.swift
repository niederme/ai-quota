import Foundation

public enum QuotaForecastTextFormatter {
    public static func detail(_ forecast: QuotaExhaustionForecast) -> String {
        let basis = forecast.basis == .weeklyPattern
            ? "Based on your usual weekly pattern" : "At your average pace this period"
        return "\(basis) · Resets \(reset(forecast))"
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
