import Foundation

/// One personal scale for every graph size and platform. Each account is
/// measured only against itself: there is no absolute token threshold. The
/// displayed period never affects the baseline, and today's incomplete usage
/// never trains it.
///
/// Steps are logarithmic against the account's "big day": the 90th percentile
/// of completed active days over the past year, or the busiest day while there
/// are fewer than ten. The four steps split the span from 1/30 of that day up
/// to it evenly, so each step is roughly 2.3× more tokens; anything above the
/// big day is the top step and anything below 1/30 of it is the first.
public struct CodexTokenActivityScale: Sendable {
    public static let explanation = "Intensity relative to your own busiest days in the past year."
    static let baselineDays = 364
    static let minimumPercentileSamples = 10
    static let referencePercentile = 0.90
    static let span = 30.0

    public let sampleCount: Int
    /// The day that reaches the top step; nil until a completed active day exists.
    public let reference: Double?

    public init(tokensByDate: [String: Double], now: Date = .now) {
        let calendar = CodexTokenHistory.calendar
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -Self.baselineDays, to: today)!
        let formatter = CodexTokenHistory.dateFormatter()
        let values = tokensByDate.compactMap { key, tokens -> Double? in
            guard tokens.isFinite, tokens > 0,
                  let date = formatter.date(from: key), formatter.string(from: date) == key,
                  date >= start, date < today else { return nil }
            return tokens
        }.sorted()
        sampleCount = values.count
        if values.isEmpty {
            reference = nil
        } else if values.count < Self.minimumPercentileSamples {
            reference = values.last
        } else {
            let position = Double(values.count - 1) * Self.referencePercentile
            let lower = Int(position)
            let upper = min(lower + 1, values.count - 1)
            reference = values[lower] + (values[upper] - values[lower]) * (position - Double(lower))
        }
    }

    /// Palette index 0...3 for a positive reading. Missing, zero and future
    /// cells remain the renderer's responsibility. With no completed active
    /// day yet, activity shows on the first step until a baseline exists.
    public func positiveLevel(for tokens: Double) -> Int {
        guard tokens.isFinite, tokens > 0, let reference, reference > 0 else { return 0 }
        if tokens >= reference { return 3 }
        let floor = reference / Self.span
        guard tokens > floor else { return 0 }
        let position = log(tokens / floor) / log(Self.span)
        return min(3, max(0, Int(position * 4)))
    }
}
