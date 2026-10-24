import Foundation
import Testing
@testable import AIQuotaKit

struct QuotaForecastTextFormatterTests {
    private let locale = Locale(identifier: "en_US_POSIX")
    private let calendar = CalendarMonthLabel.reportingCalendar
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func forecast(_ window: QuotaForecastScope.Window, earliest: String, latest: String, reset: String) -> QuotaExhaustionForecast {
        let scope = QuotaForecastScope(accountID: "sample", provider: "codex", identity: "sample-workspace",
            source: "webSession", plan: "sample", window: window, resetAt: date(reset))
        return QuotaExhaustionForecast(scope: scope, earliest: date(earliest), latest: date(latest),
            observedSpan: 86400, validUntil: date(earliest))
    }

    @Test("monthly ranges distinguish the same weekday in different weeks")
    func monthlyDatesAreExplicit() {
        let value = forecast(.monthly, earliest: "2026-10-27T12:00:00Z", latest: "2026-11-03T12:00:00Z", reset: "2026-11-10T00:00:00Z")
        let text = QuotaForecastTextFormatter.range(value, now: date("2026-10-24T00:00:00Z"), calendar: calendar, locale: locale)
        #expect(text.contains("Oct 27") && text.contains("Nov 3"))
        let reset = QuotaForecastTextFormatter.reset(value, calendar: calendar, locale: locale)
        #expect(reset.contains("Nov 10"))
    }

    @Test("short forecasts stay compact while distant weekly resets include the date")
    func shortWindowAndDistantReset() {
        let now = date("2026-10-24T00:00:00Z")
        let value = forecast(.weekly, earliest: "2026-10-25T12:00:00Z", latest: "2026-10-26T12:00:00Z", reset: "2026-10-31T00:00:00Z")
        #expect(!QuotaForecastTextFormatter.range(value, now: now, calendar: calendar, locale: locale).contains("Oct"))
        #expect(QuotaForecastTextFormatter.reset(value, now: now, calendar: calendar, locale: locale).contains("Oct 31"))
    }
}
