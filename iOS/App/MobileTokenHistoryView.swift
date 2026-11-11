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
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("tokenActivityGrid")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: graphHeight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Token activity, past \(Self.weekCount(for: availableWidth)) weeks")
            .accessibilityHint("Faint cells show days without usage. Dates are in UTC. " + CodexTokenActivityScale.explanation)
        }
    }
    /// At least a year, like the Mac. Wider cards add earlier weeks instead of
    /// enlarging cells or leaving a blank trailing strip.
    static func weekCount(for width: CGFloat) -> Int {
        max(CodexTokenHistory.visibleWeeks, Int(ceil((width + cellGap) / (maximumCellSide + cellGap))))
    }
    static func cellSide(for width: CGFloat) -> CGFloat {
        let weeks = weekCount(for: width)
        return min(maximumCellSide, max(1, (width - CGFloat(weeks - 1) * cellGap) / CGFloat(weeks)))
    }
    static func graphHeight(for width: CGFloat) -> CGFloat {
        7 * cellSide(for: width) + 6 * cellGap
    }
    private var graphHeight: CGFloat { Self.graphHeight(for: availableWidth) }
    private func fill(_ day: CodexTokenHistory.Day, scale: CodexTokenActivityScale) -> Color {
        guard !day.isFuture else { return .clear }
        guard let tokens = day.tokens, tokens > 0 else { return tokenHistoryRestingFill(colorScheme) }
        return tokenHistoryActivityFill(level: scale.positiveLevel(for: tokens), colorScheme: colorScheme)
    }

    private func description(_ day: CodexTokenHistory.Day) -> String {
        guard let tokens = day.tokens else { return "\(day.key): no record reported" }
        return "\(day.key): \(tokens.formatted(.number.precision(.fractionLength(0)))) tokens"
    }
}

// Any day without usage (reported zero, no record, or before the account
// existed) shares the dial's empty track. Only used days step up.
private func tokenHistoryRestingFill(_ colorScheme: ColorScheme) -> Color {
    OverviewStyle.overviewEmpty
}

// Four steps evenly spaced in OKLCH lightness at the dial's hue; the top step
// is exactly the dial colour, so a bright cell and a full ring agree.
private func tokenHistoryActivityFill(level: Int, colorScheme: ColorScheme) -> Color {
    let dark: [UInt32] = [0x6A4080, 0x894EA6, 0xA85CCE, 0xC86CF5]
    let light: [UInt32] = [0xCDAFE8, 0xB88AE0, 0x9F62D0, 0x8530BD]
    let hex = (colorScheme == .dark ? dark : light)[min(max(level, 0), 3)]
    return Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                 blue: Double(hex & 0xFF) / 255)
}
