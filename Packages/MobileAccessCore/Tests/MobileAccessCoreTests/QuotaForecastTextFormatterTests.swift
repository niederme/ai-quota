import Foundation
import Testing
@testable import MobileAccessCore

@Test func forecastCopyUsesAccountNameAndSupportedProviderWindow() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    for provider in ["codex", "claude"] {
        for (window, duration, label) in [
            (QuotaForecastScope.Window.fiveHour, 18000.0, "5h"),
            (.weekly, 604800.0, "7d"),
            (.monthly, 28 * 86400.0, "28d"), (.monthly, 29 * 86400.0, "29d"),
            (.monthly, 30 * 86400.0, "30d"), (.monthly, 31 * 86400.0, "31d")
        ] {
            let scope = QuotaForecastScope(accountID: "account", provider: provider, identity: "identity",
                source: "provider", plan: "plan", window: window, resetAt: now.addingTimeInterval(duration / 2))
            let input = QuotaForecastInput(scope: scope, usedPercent: 70, duration: duration, fetchedAt: now)
            let forecast = try #require(QuotaExhaustionForecast.estimate(input, now: now))
            for name in ["Codex Pro", "Claude Enterprise", "Research · Custom account", "Work."] {
                let title = "\(name) is on pace to hit its \(label) limit early"
                #expect(QuotaForecastTextFormatter.title(forecast, accountLabel: name) == title)
                let summary = QuotaForecastTextFormatter.accessibilitySummary(forecast, accountLabel: name, now: now)
                #expect(QuotaForecastTextFormatter.sentence(forecast) == "You’re on pace to hit your \(label) limit early")
                #expect(summary.hasPrefix(name + (name.hasSuffix(".") ? " " : ". ") + QuotaForecastTextFormatter.sentence(forecast) + ". "))
                #expect(summary.contains("Resets "))
                #expect(!title.contains("Resets"))
            }
        }
    }
}

@Test func forecastCopyNeverInventsMonthlyDurationOrChangesScheduledReset() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let reset = calendar.date(from: DateComponents(year: 2027, month: 1, day: 16, hour: 9, minute: 39))!
    let scope = QuotaForecastScope(accountID: "account", provider: "claude", identity: "identity",
        source: "oauth", plan: "enterprise", window: .monthly, resetAt: reset)
    for duration in [nil, 27 * 86400.0, 32 * 86400.0, 28.5 * 86400.0, .infinity, .nan] as [Double?] {
        let forecast = QuotaExhaustionForecast(scope: scope, basis: .periodAverage,
            projectedUsedPercent: 140, validUntil: reset, windowDuration: duration)
        #expect(QuotaForecastTextFormatter.title(forecast, accountLabel: "Claude Enterprise") ==
                "Claude Enterprise is on pace to hit its monthly limit early")
        #expect(QuotaForecastTextFormatter.sentence(forecast) == "You’re on pace to hit your monthly limit early")
        let detail = QuotaForecastTextFormatter.detail(forecast, now: now, calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(detail.replacingOccurrences(of: "\u{202f}", with: " ") == "At your average pace this period · Resets Sat, Jan 16 9:39 AM")
    }
}

@Test func forecastResetOmitsConnectorAndPreservesLocaleAndTimeZone() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let reset = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 16, hour: 9, minute: 39)))
    let now = reset.addingTimeInterval(-86400)
    let forecast = QuotaExhaustionForecast(scope: .init(accountID: "pro", provider: "codex", identity: "pro",
        source: "wham", plan: "pro", window: .weekly, resetAt: reset), basis: .weeklyPattern,
        projectedUsedPercent: 140, validUntil: reset)
    for (locale, expected) in [("en_US", "Sat 9:39 AM"), ("en_GB", "Sat 09:39"), ("de_DE", "Sa 09:39")] {
        let text = QuotaForecastTextFormatter.reset(forecast, now: now, calendar: calendar, locale: Locale(identifier: locale))
        #expect(text.replacingOccurrences(of: "\u{202f}", with: " ") == expected, "Locale: \(locale); actual: \(text)")
    }
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    #expect(QuotaForecastTextFormatter.reset(forecast, now: now, calendar: calendar, locale: Locale(identifier: "en_GB")) == "Sat 14:39")
}
