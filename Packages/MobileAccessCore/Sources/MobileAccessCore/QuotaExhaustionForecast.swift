import Foundation

/// A series is one app account, verified provider identity, source, plan and quota
/// window. Reset times come from the provider, never a locally guessed calendar.
public struct QuotaForecastScope: Codable, Hashable, Sendable {
    public enum Window: String, Codable, Sendable {
        case fiveHour, weekly, monthly

        public var label: String {
            switch self { case .fiveHour: "5-hour"; case .weekly: "weekly"; case .monthly: "monthly" }
        }
        var minimumSpan: TimeInterval {
            switch self { case .fiveHour: 3600; case .weekly: 12 * 3600; case .monthly: 86400 }
        }
        public var lookback: TimeInterval {
            switch self { case .fiveHour: 3 * 3600; case .weekly: 48 * 3600; case .monthly: 7 * 86400 }
        }
        var maximumGap: TimeInterval {
            switch self { case .fiveHour: 20 * 60; case .weekly: 4 * 3600; case .monthly: 8 * 3600 }
        }
        public var freshness: TimeInterval {
            switch self { case .fiveHour: 20 * 60; case .weekly: 3600; case .monthly: 4 * 3600 }
        }
        var duration: TimeInterval {
            switch self { case .fiveHour: 5 * 3600; case .weekly: 7 * 86400; case .monthly: 32 * 86400 }
        }
        public var rounding: TimeInterval {
            switch self { case .fiveHour: 3600; case .weekly: 6 * 3600; case .monthly: 12 * 3600 }
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

public struct QuotaPaceObservation: Codable, Equatable, Sendable {
    public let scope: QuotaForecastScope
    public let date: Date
    public let used: Double
    public let limit: Double

    public init(scope: QuotaForecastScope, date: Date, used: Double, limit: Double = 100) {
        self.scope = scope; self.date = date; self.used = used; self.limit = limit
    }

    public var valid: Bool {
        !scope.accountID.isEmpty && !scope.identity.isEmpty && !scope.provider.isEmpty
            && !scope.source.isEmpty && !scope.plan.isEmpty
            && date.timeIntervalSince1970.isFinite && scope.resetAt.timeIntervalSince1970.isFinite
            && used.isFinite && limit.isFinite && used >= 0 && limit > 0 && used <= limit
            && date < scope.resetAt && date >= scope.resetAt.addingTimeInterval(-scope.window.duration)
    }
}

public struct QuotaExhaustionForecast: Equatable, Sendable {
    public let scope: QuotaForecastScope
    /// An uncertainty envelope, not a countdown or a calibrated probability.
    public let earliest: Date
    public let latest: Date
    public let observedSpan: TimeInterval
    public let validUntil: Date

    public init(scope: QuotaForecastScope, earliest: Date, latest: Date,
                observedSpan: TimeInterval, validUntil: Date) {
        self.scope = scope
        self.earliest = earliest
        self.latest = latest
        self.observedSpan = observedSpan
        self.validUntil = validUntil
    }

    /// Deliberately conservative. Quiet/unstable series do not produce an insight.
    public static func estimate(scope: QuotaForecastScope, observations: [QuotaPaceObservation],
                                now: Date = .now) -> Self? {
        let policy = scope.window
        guard now.timeIntervalSince1970.isFinite, scope.resetAt > now else { return nil }
        let sorted = observations.filter { $0.scope == scope }
            .sorted { $0.date < $1.date }
        guard sorted.allSatisfy({ $0.valid && $0.date <= now }) else { return nil }
        // A drop/capacity change starts a new regime even if reset metadata did not
        // change. Never bridge a provider correction or quota wraparound.
        var regime: [QuotaPaceObservation] = []
        for sample in sorted {
            if let last = regime.last {
                if sample.date == last.date {
                    guard sample == last else { return nil }
                    continue
                }
                if sample.limit != last.limit || sample.used < last.used
                    || sample.date.timeIntervalSince(last.date) > policy.maximumGap {
                    regime.removeAll()
                }
            }
            regime.append(sample)
        }
        guard let last = regime.last, now.timeIntervalSince(last.date) <= policy.freshness,
              last.used > 0, last.used < last.limit else { return nil }
        regime.removeAll { $0.date < last.date.addingTimeInterval(-policy.lookback) }
        guard regime.count >= 7, let first = regime.first else { return nil }
        let span = last.date.timeIntervalSince(first.date)
        let gain = (last.used - first.used) / last.limit
        guard span >= policy.minimumSpan, gain >= (policy == .fiveHour ? 0.03 : 0.05) else { return nil }

        // Compare four equal-time blocks, so polling frequency cannot weight a
        // burst more heavily than an idle period. Interpolation only spans gaps
        // already bounded above. Require activity throughout the observed span.
        func value(at date: Date) -> Double {
            for (a, b) in zip(regime, regime.dropFirst()) where date <= b.date {
                let fraction = date.timeIntervalSince(a.date) / b.date.timeIntervalSince(a.date)
                return a.used + (b.used - a.used) * fraction
            }
            return last.used
        }
        let anchors = (0...4).map { value(at: first.date.addingTimeInterval(span * Double($0) / 4)) }
        let rates = zip(anchors, anchors.dropFirst()).map { ($1 - $0) / (span / 4) }
        let meanRate = (last.used - first.used) / span
        let earlyRate = rates.prefix(2).reduce(0, +)
        let recentRate = rates.suffix(2).reduce(0, +)
        guard let slowest = rates.min(), let fastest = rates.max(),
              slowest >= meanRate * 0.4, fastest <= meanRate * 2,
              recentRate >= earlyRate * 0.5, recentRate <= earlyRate * 2 else { return nil }
        let remaining = last.limit - last.used
        let early = remaining / (fastest * 1.25)
        let late = remaining / (slowest * 0.75)
        // Limit extrapolation, and suppress the whole insight if the plausible
        // exhaustion range touches reset. Do not truncate it into false certainty.
        guard early.isFinite, late.isFinite, early > 0, late <= span * 3 else { return nil }
        let rawStart = last.date.addingTimeInterval(early)
        let rawEnd = last.date.addingTimeInterval(late)
        let lower = Date(timeIntervalSince1970: floor(rawStart.timeIntervalSince1970 / policy.rounding) * policy.rounding)
        let upper = Date(timeIntervalSince1970: ceil(rawEnd.timeIntervalSince1970 / policy.rounding) * policy.rounding)
        guard lower > now, upper < scope.resetAt else { return nil }
        return Self(scope: scope, earliest: lower, latest: upper, observedSpan: span,
                    validUntil: min(lower, last.date.addingTimeInterval(policy.freshness)))
    }
}
