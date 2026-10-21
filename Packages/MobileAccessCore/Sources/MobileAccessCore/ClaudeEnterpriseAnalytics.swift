import Foundation

/// A spend report returned by Claude's Enterprise analytics service.
///
/// Dates and grouping values remain provider strings so the model does not
/// silently reinterpret an account's reporting timezone or grouping rules.
public struct ClaudeEnterpriseSpendResponse: Codable, Sendable, Equatable {
    public typealias Series = ClaudeEnterpriseSpendSeries
    public typealias Total = ClaudeEnterpriseSpendTotal
    public typealias TokenCounts = ClaudeEnterpriseTokenCounts
    public let startDate: String?
    public let endDate: String?
    public let clamped: Bool?
    public let currency: String?
    public let groupBy: String?
    public let granularity: String?
    public let series: [ClaudeEnterpriseSpendSeries]
    public let totals: [ClaudeEnterpriseSpendTotal]

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date", endDate = "end_date", clamped, currency
        case groupBy = "group_by", granularity, series, totals
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate)
        clamped = try c.decodeIfPresent(Bool.self, forKey: .clamped)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        groupBy = try c.decodeIfPresent(String.self, forKey: .groupBy)
        granularity = try c.decodeIfPresent(String.self, forKey: .granularity)
        series = try c.decodeIfPresent([ClaudeEnterpriseSpendSeries].self, forKey: .series) ?? []
        totals = try c.decodeIfPresent([ClaudeEnterpriseSpendTotal].self, forKey: .totals) ?? []
    }
}

public struct ClaudeEnterpriseSpendSeries: Codable, Sendable, Equatable {
    public let bucket: String?
    public let groupKey: String?
    public let group: String?
    public let costMinorUnits: Int?
    public let tokens: ClaudeEnterpriseTokenCounts?
    public let requestCount: Int?

    enum CodingKeys: String, CodingKey {
        case bucket, groupKey = "group_key", group
        case costMinorUnits = "cost_minor_units", tokens
        case requestCount = "request_count"
    }
}

public struct ClaudeEnterpriseTokenCounts: Codable, Sendable, Equatable {
    public let input: Int?
    public let output: Int?
    public let cacheRead: Int?
    public let cacheWrite5m: Int?
    public let cacheWrite1h: Int?

    enum CodingKeys: String, CodingKey {
        case input, output, cacheRead = "cache_read"
        case cacheWrite5m = "cache_write_5m", cacheWrite1h = "cache_write_1h"
    }
}

public struct ClaudeEnterpriseSpendTotal: Codable, Sendable, Equatable {
    public let groupKey: String?
    public let group: String?
    public let costMinorUnits: Int?
    public let percentOfTotal: Double?

    enum CodingKeys: String, CodingKey {
        case groupKey = "group_key", group
        case costMinorUnits = "cost_minor_units", percentOfTotal = "pct_of_total"
    }
}

/// Skill invocation costs. `costs` is intentionally an open JSON value because
/// the endpoint has returned null and has added provider-specific breakdowns.
public struct ClaudeEnterpriseSkillsResponse: Codable, Sendable, Equatable {
    public let startDate: String?
    public let endDate: String?
    public let clamped: Bool?
    public let items: [ClaudeEnterpriseSkillUsage]
    public let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date", endDate = "end_date", clamped, items
        case hasMore = "has_more"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate)
        clamped = try c.decodeIfPresent(Bool.self, forKey: .clamped)
        items = try c.decodeIfPresent([ClaudeEnterpriseSkillUsage].self, forKey: .items) ?? []
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore)
    }
}

public struct ClaudeEnterpriseSkillUsage: Codable, Sendable, Equatable {
    public let skillName: String?
    public let invocationCount: Int?
    public let totalCostMinorUnits: Int?
    public let attributedListPriceMinorUnits: Int?
    public let costs: ClaudeEnterpriseJSONValue?

    enum CodingKeys: String, CodingKey {
        case skillName = "skill_name", invocationCount = "invocation_count"
        case totalCostMinorUnits = "total_cost_minor_units"
        case attributedListPriceMinorUnits = "attributed_list_price_minor_units"
        case costs
    }
}

// Shared names used by the native detail surfaces.
public typealias ClaudeSpendHistory = ClaudeEnterpriseSpendResponse
public typealias ClaudeSkillUsage = ClaudeEnterpriseSkillUsage

/// Claude's analytics buckets are calendar dates in UTC, not instants. Keep
/// their day identity when a chart or label is rendered in a local time zone.
public enum ClaudeEnterpriseDateOnly {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    public static func bucketDate(_ value: String) -> Date? {
        guard value.count == 10 || (value.count > 10 && value.dropFirst(10).first == "T") else { return nil }
        let parts = value.prefix(10).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        let calendar = utcCalendar
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              calendar.dateComponents([.year, .month, .day], from: date)
                == DateComponents(year: year, month: month, day: day) else { return nil }
        return date
    }

    public static func dayBefore(_ value: String) -> String? {
        guard let date = bucketDate(value),
              let previous = utcCalendar.date(byAdding: .day, value: -1, to: date) else { return nil }
        return dateString(previous)
    }

    public static func displayDate(_ value: String) -> String? {
        guard let date = bucketDate(value) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    public static func displayRange(startDate: String, endDate: String) -> String? {
        guard let start = bucketDate(startDate), let end = bucketDate(endDate), start <= end else { return nil }
        let calendar = utcCalendar
        let a = calendar.dateComponents([.year, .month, .day], from: start)
        let b = calendar.dateComponents([.year, .month, .day], from: end)
        guard let first = displayDate(startDate), let last = displayDate(endDate) else { return nil }
        let compact = if a.year == b.year && a.month == b.month {
            "\(first.components(separatedBy: " ").first ?? "") \(a.day ?? 1)–\(b.day ?? 1), \(b.year ?? 0)"
        } else if a.year == b.year {
            "\(first.replacingOccurrences(of: ", \(a.year ?? 0)", with: "")) – \(last)"
        } else {
            "\(first) – \(last)"
        }
        return compact + " · UTC"
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// Codable representation for provider-specific fields whose shape is not
/// stable yet. It keeps non-null values available without making the core
/// skill metrics fragile when `costs` is null or changes shape.
public enum ClaudeEnterpriseJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: ClaudeEnterpriseJSONValue])
    case array([ClaudeEnterpriseJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? c.decode(Int.self) { self = .number(Double(value)) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([String: ClaudeEnterpriseJSONValue].self) { self = .object(value) }
        else if let value = try? c.decode([ClaudeEnterpriseJSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .boolean(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .null: try c.encodeNil()
        }
    }
}
