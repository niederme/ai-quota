import Foundation

/// One personal scale for every graph size and platform. The displayed period
/// never affects the baseline, and today's incomplete usage never trains it.
public struct CodexTokenActivityScale: Sendable {
    public static let explanation = "Intensity relative to your last 90 days of token usage."
    public let sampleCount: Int
    private let thresholds: [Double]

    public init(tokensByDate: [String: Double], now: Date = .now) {
        let calendar = CodexTokenHistory.calendar
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -90, to: today)!
        let formatter = CodexTokenHistory.dateFormatter()
        let values = tokensByDate.compactMap { key, tokens -> Double? in
            guard tokens.isFinite, tokens > 0,
                  let date = formatter.date(from: key), formatter.string(from: date) == key,
                  date >= start, date < today else { return nil }
            return tokens
        }.sorted()
        sampleCount = values.count
        // Interpolate counts rather than ranking each cell. Ties stay together;
        // a uniform baseline stays muted instead of becoming 100th percentile.
        thresholds = values.isEmpty ? [] : [0.50, 0.80, 0.95].map { fraction in
            let position = Double(values.count - 1) * fraction
            let lower = Int(position)
            let upper = min(lower + 1, values.count - 1)
            return values[lower] + (values[upper] - values[lower]) * (position - Double(lower))
        }
    }

    /// Palette index 0...3 for a positive reading. Missing, zero and future
    /// cells remain the renderer's responsibility. With no completed active
    /// days, show activity quietly until a personal baseline is available.
    public func positiveLevel(for tokens: Double) -> Int {
        guard tokens.isFinite, tokens > 0, !thresholds.isEmpty else { return 0 }
        return thresholds.firstIndex(where: { tokens <= $0 }) ?? 3
    }
}
