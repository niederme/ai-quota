import Foundation

/// Analytics always retains calendar gaps and labels partial attribution.
public struct CodexHistoryPeriod: Sendable {
    public enum Breakdown: String, CaseIterable, Sendable { case models, surfaces }
    public struct Series: Identifiable, Sendable {
        public let id: String
        public let total: Double
        /// nil means unavailable; a missing category in a reported map means zero.
        public let values: [Double?]
    }
    public let days: [CodexUsageHistory.Day]
    public init(history: CodexUsageHistory?, count: Int) {
        days = Array((history?.days ?? []).suffix(max(0, count)))
    }
    public var total: Double { days.compactMap(\.credits).reduce(0, +) }
    public var reportedDays: Int { days.filter { $0.credits != nil }.count }
    public var isPartial: Bool { reportedDays < days.count }
    public func series(_ breakdown: Breakdown) -> [Series] {
        func map(_ day: CodexUsageHistory.Day) -> [String: Double]? {
            guard day.credits != nil else { return nil }
            return breakdown == .models ? day.models : day.surfaces
        }
        let keys = Set(days.flatMap { map($0)?.keys.map { $0 } ?? [] })
        return keys.map { key in
            let values = days.map { day -> Double? in
                guard let values = map(day), !values.isEmpty else { return nil }
                return values[key] ?? 0
            }
            return Series(id: key, total: values.compactMap { $0 }.reduce(0, +), values: values)
        }.filter { $0.total > 0 }.sorted {
            $0.total == $1.total ? $0.id < $1.id : $0.total > $1.total
        }
    }
    public func missingAttribution(_ breakdown: Breakdown) -> Bool {
        days.contains { day in
            guard let credits = day.credits, credits > 0 else { return false }
            return (breakdown == .models ? day.models : day.surfaces)?.isEmpty ?? true
        }
    }
    public static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
