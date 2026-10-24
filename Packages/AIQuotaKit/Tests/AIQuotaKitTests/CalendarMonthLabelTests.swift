import AIQuotaKit
import Foundation
import Testing

@Suite("Calendar month quota labels")
struct CalendarMonthLabelTests {
    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    @Test("month labels include Gregorian leap-year and century rules", arguments: [
        ("2026-01-15T12:00:00Z", "31d"),
        ("2026-04-15T12:00:00Z", "30d"),
        ("2026-02-15T12:00:00Z", "28d"),
        ("2024-02-29T12:00:00Z", "29d"),
        ("2000-02-29T12:00:00Z", "29d"),
        ("2100-02-28T12:00:00Z", "28d")
    ])
    func monthLengths(input: String, expected: String) {
        #expect(CalendarMonthLabel.compact(containing: date(input)) == expected)
    }

    @Test("UTC reporting boundaries include month and year transitions", arguments: [
        ("2024-02-29T23:59:59Z", "29d"),
        ("2024-03-01T00:00:00Z", "31d"),
        ("2026-04-30T23:59:59Z", "30d"),
        ("2026-05-01T00:00:00Z", "31d"),
        ("2026-12-31T23:59:59Z", "31d"),
        ("2027-01-01T00:00:00Z", "31d")
    ])
    func reportingBoundaries(input: String, expected: String) {
        #expect(CalendarMonthLabel.compact(containing: date(input)) == expected)
    }

    @Test("a retained budget keeps its reading month after a partial refresh")
    func retainedReadingMonth() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let initial = try decoder.decode(WhamUsageResponse.self, from: Data(#"{"plan_type":"team","spend_control":{"individual_limit":{"unit":"credit","used":"8.22","limit":"7000"}}}"#.utf8))
        let partial = try decoder.decode(WhamUsageResponse.self, from: Data(#"{"plan_type":"team"}"#.utf8))
        let oldReading = CodexUsage(from: initial, fetchedAt: date("2026-04-30T23:59:59Z"))
        let newReading = CodexUsage(from: partial, fetchedAt: date("2026-05-01T00:00:01Z"))
            .retainingLastConfirmedWindows(from: oldReading)
        #expect(CalendarMonthLabel.compact(containing: newReading.fetchedAt) == "30d")
        #expect(newReading.monthlyBudget?.used == 8.22)
    }

    @Test("calendar arithmetic survives DST and an explicit reporting timezone")
    func timezoneAndDST() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let boundary = date("2026-05-01T00:30:00Z")
        #expect(CalendarMonthLabel.compact(containing: boundary) == "31d")
        #expect(CalendarMonthLabel.compact(containing: boundary, calendar: newYork) == "30d")
        #expect(CalendarMonthLabel.compact(containing: date("2026-03-15T12:00:00Z"), calendar: newYork) == "31d")
        #expect(CalendarMonthLabel.compact(containing: date("2026-11-15T12:00:00Z"), calendar: newYork) == "30d")
    }

    @Test("spoken labels identify calendar context")
    func spokenContext() {
        #expect(CalendarMonthLabel.spoken(containing: date("2024-02-29T12:00:00Z")) == "29 day calendar month")
    }
}
