import SwiftUI
import MobileAccessCore

/// Profile tokens, never the credit-spending history shown in service analytics.
struct MobileTokenHistoryView: View {
    static let cellGap: CGFloat = 1
    static let maximumCellSide: CGFloat = 9
    let history: CodexTokenHistory?
    let unavailable: Bool
    let loading: Bool
    var availableWidth: CGFloat = 288
    @Environment(\.colorScheme) private var colorScheme

    enum Presentation: Equatable { case loading, empty, unavailable, populated }
    static func presentation(history: CodexTokenHistory?, unavailable: Bool, loading: Bool, now: Date = .now, weeks: Int = CodexTokenHistory.visibleWeeks) -> Presentation {
        if let history {
            return history.days(now: now, weeks: weeks).contains { !$0.isFuture && $0.tokens != nil } ? .populated : .empty
        }
        return loading ? .loading : .unavailable
    }
    private var presentation: Presentation { Self.presentation(history: history, unavailable: unavailable, loading: loading, weeks: Self.weekCount(for: availableWidth)) }

    var body: some View {
        if let history, presentation == .populated {
            let now = Date.now
            let scale = CodexTokenActivityScale(tokensByDate: history.tokensByDate, now: now)
            GeometryReader { geometry in
                let weeks = Self.weekCount(for: geometry.size.width)
                let days = history.days(now: now, weeks: weeks)
                let gap = Self.cellGap
                let side = Self.cellSide(for: geometry.size.width)
                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<weeks, id: \.self) { week in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                let day = days[week * 7 + row]
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(fill(day, scale: scale))
                                    .frame(width: side, height: side)
                                    .accessibilityLabel(day.isToday ? "Today, \(description(day))" : description(day))
                                    .accessibilityHidden(day.isFuture)
                            }
                        }
                    }
                }
                .frame(minHeight: 44, alignment: .top)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("tokenActivityGrid")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: graphHeight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Token activity, past \(Self.weekCount(for: availableWidth)) weeks")
            .accessibilityHint("Dim cells have no record. Dates are in UTC. " + CodexTokenActivityScale.explanation)
        }
    }
    /// Add earlier weeks instead of enlarging cells or leaving a blank trailing strip.
    static func weekCount(for width: CGFloat) -> Int {
        max(CodexTokenHistory.visibleWeeks, Int(ceil((width + cellGap) / (maximumCellSide + cellGap))))
    }
    static func cellSide(for width: CGFloat) -> CGFloat {
        let weeks = weekCount(for: width)
        return min(maximumCellSide, max(1, (width - CGFloat(weeks - 1) * cellGap) / CGFloat(weeks)))
    }
    static func graphHeight(for width: CGFloat) -> CGFloat {
        max(44, 7 * cellSide(for: width) + 6 * cellGap)
    }
    private var graphHeight: CGFloat { Self.graphHeight(for: availableWidth) }
    private func fill(_ day: CodexTokenHistory.Day, scale: CodexTokenActivityScale) -> Color {
        guard !day.isFuture else { return .clear }
        guard let tokens = day.tokens else { return Color.secondary.opacity(0.18) }
        if tokens == 0 {
            return colorScheme == .dark
                ? Color(red: 0.30, green: 0.28, blue: 0.34)
                : Color(red: 0.87, green: 0.85, blue: 0.90)
        }
        let colors: [Color] = colorScheme == .dark ? [
            Color(red: 0.32, green: 0.19, blue: 0.42),
            Color(red: 0.47, green: 0.27, blue: 0.61),
            Color(red: 0.64, green: 0.33, blue: 0.81),
            Color(red: 0.77, green: 0.42, blue: 0.94)
        ] : [
            Color(red: 0.82, green: 0.67, blue: 0.94),
            Color(red: 0.68, green: 0.44, blue: 0.86),
            Color(red: 0.53, green: 0.25, blue: 0.74),
            Color(red: 0.37, green: 0.12, blue: 0.57)
        ]
        return colors[scale.positiveLevel(for: tokens)]
    }
    private func description(_ day: CodexTokenHistory.Day) -> String {
        guard let tokens = day.tokens else { return "\(day.key): no record reported" }
        return "\(day.key): \(tokens.formatted(.number.precision(.fractionLength(0)))) tokens"
    }
}
