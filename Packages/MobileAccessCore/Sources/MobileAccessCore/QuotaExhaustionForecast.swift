import Foundation

/// A series is one app account, verified provider identity, source, plan and quota
/// window. Reset times come from the provider, never a locally guessed calendar.
public struct QuotaForecastScope: Codable, Hashable, Sendable {
    public enum Window: String, Codable, Sendable {
        case fiveHour, weekly, monthly

        public var label: String {
            switch self { case .fiveHour: "5-hour"; case .weekly: "weekly"; case .monthly: "monthly" }
        }
        public var freshness: TimeInterval {
            switch self { case .fiveHour: 20 * 60; case .weekly: 3600; case .monthly: 4 * 3600 }
        }
    }

    public let accountID: String
    public let provider: String
    public let identity: String
    public let source: String
    public let plan: String
    public let window: Window
    public let resetAt: Date

    public init(accountID: String, provider: String, identity: String, source: String,
                plan: String, window: Window, resetAt: Date) {
        self.accountID = accountID; self.provider = provider; self.identity = identity
        self.source = source; self.plan = plan; self.window = window
        self.resetAt = Date(timeIntervalSince1970: resetAt.timeIntervalSince1970.rounded())
    }
}

/// An ephemeral provider-history snapshot, never a locally accumulated series.
/// Values may be tokens or credits: only their relative weekday pattern is used.
public struct QuotaForecastDailyHistory: Equatable, Sendable {
    public let values: [String: Double]
    public let fetchedAt: Date
    public init(values: [String: Double], fetchedAt: Date) {
        self.values = values; self.fetchedAt = fetchedAt
    }
    public init(_ history: CodexUsageHistory) {
        values = history.days.reduce(into: [:]) { result, day in
            if let credits = day.credits { result[day.date] = credits }
        }
        fetchedAt = history.fetchedAt
    }
}

public struct QuotaForecastInput: Equatable, Sendable {
    public let scope: QuotaForecastScope
    public let usedPercent: Double
    public let duration: TimeInterval
    public let fetchedAt: Date
    public init(scope: QuotaForecastScope, usedPercent: Double, duration: TimeInterval, fetchedAt: Date) {
        self.scope = scope; self.usedPercent = usedPercent; self.duration = duration; self.fetchedAt = fetchedAt
    }
    public static func inputs(for reading: QuotaReading, accountID: String, provider: String) -> [Self] {
        guard let identity = reading.providerIdentity, !identity.isEmpty,
              let plan = reading.metadata?.plan, !plan.isEmpty, plan.lowercased() != "unknown",
              provider == "codex" || provider == "claude" else { return [] }
        // Budget-only responses supply no period start/duration. Do not invent a
        // calendar month, including the synthetic 30-day primaryDisplayWindow.
        return reading.windows.compactMap { value in
            guard let reset = value.resetsAt else { return nil }
            let window: QuotaForecastScope.Window
            switch value.durationSeconds {
            case 18000: window = .fiveHour
            case 604800: window = .weekly
            case 28 * 86400...31 * 86400: window = .monthly
            default: return nil
            }
            return Self(scope: .init(accountID: accountID, provider: provider, identity: identity,
                source: provider == "codex" ? "wham" : "oauth", plan: plan, window: window, resetAt: reset),
                usedPercent: value.usedPercent, duration: Double(value.durationSeconds), fetchedAt: reading.fetchedAt)
        }
    }
}

/// A before-reset warning, not an exhaustion clock or a calibrated probability.
public struct QuotaExhaustionForecast: Equatable, Sendable {
    public enum Basis: Sendable { case periodAverage, weeklyPattern }
    public let scope: QuotaForecastScope
    public let basis: Basis
    public let projectedUsedPercent: Double
    public let validUntil: Date

    public init(scope: QuotaForecastScope, basis: Basis, projectedUsedPercent: Double, validUntil: Date) {
        self.scope = scope; self.basis = basis
        self.projectedUsedPercent = projectedUsedPercent; self.validUntil = validUntil
    }

    public static func estimate(_ input: QuotaForecastInput, history: QuotaForecastDailyHistory? = nil,
                                now: Date = .now) -> Self? {
        let scope = input.scope
        guard !scope.accountID.isEmpty, !scope.identity.isEmpty, !scope.plan.isEmpty,
              scope.plan.lowercased() != "unknown", !scope.source.isEmpty,
              ["codex", "claude"].contains(scope.provider),
              now.timeIntervalSince1970.isFinite, input.fetchedAt.timeIntervalSince1970.isFinite,
              scope.resetAt.timeIntervalSince1970.isFinite, scope.resetAt > now,
              input.fetchedAt <= now, now.timeIntervalSince(input.fetchedAt) <= scope.window.freshness,
              input.usedPercent.isFinite, input.usedPercent > 0, input.usedPercent < 100 else { return nil }
        switch scope.window {
        case .fiveHour: guard input.duration == 18000 else { return nil }
        case .weekly: guard input.duration == 604800 else { return nil }
        case .monthly: guard (28 * 86400...31 * 86400).contains(input.duration) else { return nil }
        }
        let start = scope.resetAt.addingTimeInterval(-input.duration)
        let elapsed = input.fetchedAt.timeIntervalSince(start)
        // This is time in the provider's period, not time since app installation.
        let minimumElapsed: TimeInterval = scope.window == .fiveHour ? 1800 : 86400
        guard elapsed >= minimumElapsed, elapsed < input.duration else { return nil }
        var ratio = input.duration / elapsed
        var basis = Basis.periodAverage
        if scope.window != .fiveHour, let history,
           let weights = weekdayWeights(history, now: input.fetchedAt) {
            // Daily totals cannot tell us when someone works, including nights.
            // Count every touched past day in full, and only complete future
            // days. This deliberately understates risk across partial days
            // rather than assuming activity is uniform or follows office hours.
            let past = weightedDays(from: start, to: input.fetchedAt, weights: weights, includePartial: true)
            let future = weightedDays(from: input.fetchedAt, to: scope.resetAt, weights: weights, includePartial: false)
            if past > 0 {
                ratio = (past + future) / past
                basis = .weeklyPattern
            }
        }
        let projected = input.usedPercent * ratio
        // Leave a margin for rounded readings and modest changes in behavior.
        guard projected.isFinite, projected >= 110 else { return nil }
        return Self(scope: scope, basis: basis, projectedUsedPercent: projected,
                    validUntil: min(scope.resetAt, input.fetchedAt.addingTimeInterval(scope.window.freshness)))
    }

    /// Validate on the most recent complete week using only the preceding three.
    /// Missing days never become zero; today and future buckets never train the fit.
    static func weekdayWeights(_ history: QuotaForecastDailyHistory, now: Date) -> [Double]? {
        guard history.fetchedAt <= now.addingTimeInterval(300),
              now.timeIntervalSince(history.fetchedAt) <= 36 * 3600 else { return nil }
        let calendar = CodexTokenHistory.calendar
        let today = calendar.startOfDay(for: now)
        let formatter = CodexTokenHistory.dateFormatter()
        let days = (1...28).reversed().map { today.addingTimeInterval(-Double($0) * 86400) }
        var values: [Double] = []
        for day in days {
            guard let value = history.values[formatter.string(from: day)], value.isFinite, value >= 0 else { return nil }
            values.append(value)
        }
        // Winsorization keeps a single burst from defining a weekday. Do not
        // infer a schedule from only one or two active days in four weeks.
        let positive = values.filter { $0 > 0 }.sorted()
        guard positive.count >= 8 else { return nil }
        func fit(_ count: Int, weekday: Int?) -> Double {
            let positive = (0..<count).filter {
                (weekday == nil || calendar.component(.weekday, from: days[$0]) == weekday) && values[$0] > 0
            }.map { values[$0] }.sorted()
            guard !positive.isEmpty else { return 0 }
            let quantile = weekday == nil ? Int(Double(positive.count - 1) * 0.9) : positive.count / 2
            let cap = positive[quantile] * 3
            var sum = 0.0, weight = 0.0
            for i in 0..<count where weekday == nil || calendar.component(.weekday, from: days[i]) == weekday {
                let w = pow(0.8, Double((count - 1 - i) / 7))
                sum += min(values[i], cap) * w; weight += w
            }
            return weight > 0 ? sum / weight : 0
        }
        let baseline = fit(21, weekday: nil)
        guard baseline > 0 else { return nil }
        var averageError = 0.0, weekdayError = 0.0, actualTotal = 0.0
        for i in 21..<28 {
            let predicted = fit(21, weekday: calendar.component(.weekday, from: days[i]))
            averageError += abs(values[i] - baseline)
            weekdayError += abs(values[i] - predicted)
            actualTotal += values[i]
        }
        guard actualTotal > 0, averageError > 0,
              weekdayError < averageError * 0.9, weekdayError / actualTotal <= 0.35 else { return nil }
        let mean = fit(28, weekday: nil)
        return (1...7).map { weekday in
            // Shrink modestly toward a flat week, retaining uncertainty on quiet days.
            0.1 + 0.9 * fit(28, weekday: weekday) / mean
        }
    }

    private static func weightedDays(from start: Date, to end: Date, weights: [Double], includePartial: Bool) -> Double {
        let calendar = CodexTokenHistory.calendar
        var cursor = start, total = 0.0
        while cursor < end {
            let next = min(end, calendar.startOfDay(for: cursor).addingTimeInterval(86400))
            let complete = cursor == calendar.startOfDay(for: cursor) && next.timeIntervalSince(cursor) == 86400
            if includePartial || complete {
                total += weights[calendar.component(.weekday, from: cursor) - 1]
            }
            cursor = next
        }
        return total
    }
}
