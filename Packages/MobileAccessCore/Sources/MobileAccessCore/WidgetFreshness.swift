import Foundation

public enum WidgetFreshness {
    public static func isOld(_ reading: QuotaReading?, at date: Date) -> Bool {
        guard let reading else { return true }
        return date < reading.fetchedAt || date.timeIntervalSince(reading.fetchedAt) >= 1800 ||
            [reading.shortTerm?.resetsAt, reading.weekly?.resetsAt].compactMap { $0 }.contains { $0 <= date }
    }
    public static func boundaries(_ reading: QuotaReading?, after date: Date) -> [Date] {
        guard let reading else { return [] }
        return Array(Set([reading.fetchedAt.addingTimeInterval(1800), reading.shortTerm?.resetsAt,
                          reading.weekly?.resetsAt].compactMap { $0 }.filter { $0 > date })).sorted()
    }
    public static func limitReached(_ reading: QuotaReading?) -> Bool {
        reading?.shortTerm?.usedPercent == 100 || reading?.weekly?.usedPercent == 100
    }
}
