import Foundation

/// Provider-reported product percentages. Their denominator is not inferred or normalized.
public struct ClaudeWeeklyBreakdown: Codable, Sendable, Equatable {
    public struct Row: Codable, Sendable, Equatable, Identifiable {
        public let key: String
        public let displayName: String
        public let percent: Double
        public var id: String { key }
        enum CodingKeys: String, CodingKey { case key, displayName = "display_name", percent }
    }
    public let asOf: Date
    public let windowStartedAt: Date
    public let rows: [Row]
    enum CodingKeys: String, CodingKey { case asOf = "as_of", windowStartedAt = "window_started_at", rows }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func date(_ key: CodingKeys) throws -> Date {
            // Native cache dates and API ISO-8601 strings are both supported.
            if let value = try? c.decode(Date.self, forKey: key) { return value }
            let text = try c.decode(String.self, forKey: key)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let value = f.date(from: text) { return value }
            f.formatOptions = [.withInternetDateTime]
            guard let value = f.date(from: text) else { throw AccessError.invalidResponse }
            return value
        }
        asOf = try date(.asOf)
        windowStartedAt = try date(.windowStartedAt)
        rows = try c.decode([Row].self, forKey: .rows)
        guard windowStartedAt <= asOf, !rows.isEmpty,
              Set(rows.map(\.key)).count == rows.count,
              rows.allSatisfy({ !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && $0.percent.isFinite && (0...100).contains($0.percent) }) else {
            throw AccessError.invalidResponse
        }
    }
}
