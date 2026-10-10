import Foundation

/// Profile token counts are independent of quota credits. Omitted dates stay unknown.
public struct CodexTokenHistory: Codable, Sendable {
    public let tokensByDate: [String: Double]
    public let fetchedAt: Date
    public let scopeID: String?

    public struct Day: Identifiable, Sendable {
        public let date: Date
        public let key: String
        public let tokens: Double?
        public let isFuture: Bool
        public let isToday: Bool
        public var id: String { key }
    }

    private struct Response: Decodable {
        let page: Page?
        struct Page: Decodable { let activity_graph: Graph? }
        struct Graph: Decodable { let daily_usage_buckets: [Bucket]? }
        struct Bucket: Decodable { let start_date: String; let tokens: Double }
    }

    public static func decode(_ data: Data, fetchedAt: Date = .now, scopeID: String? = nil) throws -> Self? {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let buckets = response.page?.activity_graph?.daily_usage_buckets else { return nil }
        var values: [String: Double] = [:]
        let formatter = dateFormatter()
        for bucket in buckets {
            guard let date = formatter.date(from: bucket.start_date),
                  formatter.string(from: date) == bucket.start_date,
                  bucket.tokens.isFinite, bucket.tokens >= 0,
                  values[bucket.start_date] == nil else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid token history bucket"))
            }
            values[bucket.start_date] = bucket.tokens
        }
        return Self(tokensByDate: values, fetchedAt: fetchedAt, scopeID: scopeID)
    }

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }

    public static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    /// 52 Sunday-first columns; the current week is always the rightmost.
    public func days(now: Date = .now) -> [Day] {
        let calendar = Self.calendar
        let today = calendar.startOfDay(for: now)
        let sunday = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: today) - 1), to: today)!
        let start = calendar.date(byAdding: .day, value: -51 * 7, to: sunday)!
        let formatter = Self.dateFormatter()
        return (0..<364).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let key = formatter.string(from: date)
            return Day(date: date, key: key, tokens: tokensByDate[key], isFuture: date > today, isToday: date == today)
        }
    }
}

/// One validated profile snapshot. Its opaque scope prevents a saved graph from
/// appearing for a different account after credentials change.
public struct CodexTokenHistoryCache {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "mobileProbe.codexTokenHistory") {
        self.defaults = defaults
        self.key = key
    }

    public func load(scopeID: String?) -> CodexTokenHistory? {
        guard let scopeID, let data = defaults.data(forKey: key) else { return nil }
        let formatter = CodexTokenHistory.dateFormatter()
        guard let history = try? JSONDecoder().decode(CodexTokenHistory.self, from: data),
              history.scopeID == scopeID,
              history.tokensByDate.allSatisfy({ date, tokens in
                  guard let parsed = formatter.date(from: date) else { return false }
                  return formatter.string(from: parsed) == date && tokens.isFinite && tokens >= 0
              }) else {
            clear()
            return nil
        }
        return history
    }

    public func save(_ history: CodexTokenHistory) {
        guard history.scopeID != nil, let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() { defaults.removeObject(forKey: key) }
}

/// Unknown identities are never treated as the same account across refreshes.
public struct CodexTokenHistoryScope: Sendable {
    private var initialized = false
    private var scopeID: String?

    public init() {}

    /// Returns true when an existing in-memory history must be discarded.
    public mutating func update(scopeID: String?) -> Bool {
        let changed = !initialized || scopeID == nil || self.scopeID != scopeID
        self.scopeID = scopeID
        initialized = true
        return changed
    }
}
