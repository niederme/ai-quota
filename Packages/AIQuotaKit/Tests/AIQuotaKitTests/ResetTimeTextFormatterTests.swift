import AIQuotaKit
import Foundation
import Testing

@Suite("Reset time text formatter")
struct ResetTimeTextFormatterTests {
    private let locale = Locale(identifier: "en_US_POSIX")
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    @Test("same-day resets show today and the local time compactly")
    func sameDayResetUsesTodayAndTime() {
        let now = date(year: 2026, month: 4, day: 17, hour: 17, minute: 55)
        let resetAt = date(year: 2026, month: 4, day: 17, hour: 20, minute: 29)

        let formatted = ResetTimeTextFormatter.windowCaption(
            "5h",
            resetAt: resetAt,
            now: now,
            calendar: calendar,
            locale: locale
        )

        #expect(formatted == "5h resets Today 8:29pm")
    }

    @Test("next-day resets show tomorrow and the local time compactly")
    func nextDayResetUsesTomorrowAndTime() {
        let now = date(year: 2026, month: 4, day: 17, hour: 17, minute: 55)
        let resetAt = date(year: 2026, month: 4, day: 18, hour: 0, minute: 15)

        let formatted = ResetTimeTextFormatter.windowCaption(
            "5h",
            resetAt: resetAt,
            now: now,
            calendar: calendar,
            locale: locale
        )

        #expect(formatted == "5h resets Tomorrow 12:15am")
    }

    @Test("future-day resets show the weekday and time")
    func futureDayResetUsesWeekdayAndTime() {
        let now = date(year: 2026, month: 4, day: 17, hour: 17, minute: 55)
        let resetAt = date(year: 2026, month: 4, day: 22, hour: 13, minute: 3)

        let formatted = ResetTimeTextFormatter.windowCaption(
            "7d",
            resetAt: resetAt,
            now: now,
            calendar: calendar,
            locale: locale
        )

        #expect(formatted == "7d resets Wed. 1:03pm")
    }

    @Test("missing reset dates degrade gracefully")
    func missingResetDateUsesFallback() {
        let formatted = ResetTimeTextFormatter.windowCaption(
            "5h",
            resetAt: nil,
            locale: locale
        )

        #expect(formatted == "5h resets soon")
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
