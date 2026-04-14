import AIQuotaKit
import Testing

@Suite("Countdown text formatter")
struct CountdownTextFormatterTests {
    @Test("full style switches to days when appropriate")
    func fullStyleUsesDayHourBreakdown() {
        let formatted = CountdownTextFormatter.duration((45 * 3_600) + (39 * 60))
        #expect(formatted == "1 day, 21 hours")
    }

    @Test("full style includes minutes below one day")
    func fullStyleUsesHoursAndMinutes() {
        let formatted = CountdownTextFormatter.duration((2 * 3_600) + (15 * 60))
        #expect(formatted == "2 hours, 15 minutes")
    }

    @Test("compact style stays short for tight UI")
    func compactStyleUsesAbbreviatedUnits() {
        let formatted = CountdownTextFormatter.duration((45 * 3_600) + (39 * 60), style: .compact)
        #expect(formatted == "1d 21h")
    }

    @Test("sub-minute values are still human readable")
    func subMinuteValues() {
        #expect(CountdownTextFormatter.duration(0) == "less than a minute")
        #expect(CountdownTextFormatter.duration(0, style: .compact) == "<1m")
    }
}
