import Foundation

/// Server-reported daily usage credits. A missing day is not assumed to be zero.
public struct CodexUsageHistory: Codable, Sendable, Equatable {
    public struct Day: Codable, Sendable, Equatable, Identifiable {
        public let date: String
        public let credits: Double?
        public var models: [String: Double]? = nil
        public var surfaces: [String: Double]? = nil
        public var id: String { date }
    }
    public let fetchedAt: Date
    public let days: [Day]
    /// Begin with actual usage, retaining zero and missing days after that point.
    /// The overview reserves 30 slots so new accounts fill from left to right.
    public var chartDays: [Day] {
        Array(days.drop(while: { ($0.credits ?? 0) <= 0 }))
    }
    public var hasChartData: Bool { !chartDays.isEmpty }
    public var chartRangeLabel: String {
        guard let first = chartDays.first, let last = chartDays.last else { return "" }
        let end = last.date == Self.dateString(.now) ? "Today" : Self.axisLabel(last.date)
        return first.date == last.date ? end : "\(Self.axisLabel(first.date)) – \(end)"
    }
    public var startLabel: String { days.first.map { Self.axisLabel($0.date) } ?? "" }
    public var endLabel: String {
        days.last?.date == Self.dateString(.now) ? "Today" : days.last.map { Self.axisLabel($0.date) } ?? ""
    }
    private static func axisLabel(_ value: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return value }
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
    // Provider dates are calendar dates without a zone. Use UTC consistently rather
    // than shifting buckets according to the phone's current time zone.
    public static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    public static func decode(_ data: Data, now: Date) throws -> Self {
        struct Response: Decodable {
            struct Row: Decodable {
                let date: String
                let product_surface_usage_values: [String: Double]
                struct Model: Decodable {
                    let model: String?
                    let credits: Double
                }
                let models: [Model]?
            }
            let data: [Row]
        }
        let rows = try JSONDecoder().decode(Response.self, from: data).data
        var values: [String: Double] = [:]
        var models: [String: [String: Double]] = [:]
        var surfaces: [String: [String: Double]] = [:]
        for row in rows {
            // Model and surface values describe the same usage. Sum surfaces once.
            guard values[row.date] == nil, !row.product_surface_usage_values.isEmpty,
                  row.product_surface_usage_values.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                throw AccessError.invalidResponse
            }
            let total = row.product_surface_usage_values.values.reduce(0, +)
            guard total.isFinite else { throw AccessError.invalidResponse }
            values[row.date] = total
            surfaces[row.date] = row.product_surface_usage_values
            if let entries = row.models, !entries.isEmpty,
               entries.allSatisfy({ $0.model != nil && $0.credits.isFinite && $0.credits >= 0 }) {
                var breakdown: [String: Double] = [:]
                for entry in entries { breakdown[entry.model!, default: 0] += entry.credits }
                if breakdown.values.allSatisfy({ $0.isFinite }) { models[row.date] = breakdown }
            }
        }
        let days = (0..<30).reversed().map { offset in
            let date = dateString(now.addingTimeInterval(-Double(offset) * 86400))
            return Day(date: date, credits: values[date], models: models[date], surfaces: surfaces[date])
        }
        return Self(fetchedAt: now, days: days)
    }
}
