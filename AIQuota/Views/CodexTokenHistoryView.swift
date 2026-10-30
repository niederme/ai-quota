import SwiftUI
import AIQuotaKit
import struct MobileAccessCore.CodexTokenActivityScale

/// Profile tokens, never the credit-spending history shown in service analytics.
struct CodexTokenHistoryView: View {
    static let weeks = 52
    static let cellGap: CGFloat = 1

    let history: CodexTokenHistory
    let availableWidth: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let now = Date.now
        let days = Array(history.days(now: now).suffix(Self.weeks * 7))
        let scale = CodexTokenActivityScale(tokensByDate: history.tokensByDate, now: now)
        let side = Self.cellSide(for: availableWidth)
        let gridWidth = CGFloat(Self.weeks) * side + CGFloat(Self.weeks - 1) * Self.cellGap

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Self.cellGap) {
                ForEach(0..<Self.weeks, id: \.self) { week in
                    VStack(spacing: Self.cellGap) {
                        ForEach(0..<7, id: \.self) { row in
                            let day = days[week * 7 + row]
                            RoundedRectangle(cornerRadius: 1)
                                .fill(fill(day, scale: scale))
                                .frame(width: side, height: side)
                                .help(day.isFuture ? "" : description(day) + "\n" + CodexTokenActivityScale.explanation)
                                .accessibilityLabel(description(day))
                                .accessibilityHidden(day.isFuture)
                        }
                    }
                }
            }
            .frame(width: gridWidth, height: 7 * side + 6 * Self.cellGap, alignment: .topLeading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tokenActivityGrid")
        }
        .frame(width: availableWidth, height: Self.graphHeight(for: availableWidth), alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Token activity, past 52 weeks")
        .accessibilityHint("Dates are in UTC. Token counts are separate from monthly credit usage. " + CodexTokenActivityScale.explanation)
        .accessibilityIdentifier("codexTokenActivity")
    }

    static func cellSide(for width: CGFloat) -> CGFloat {
        max(1, (width - CGFloat(weeks - 1) * cellGap) / CGFloat(weeks))
    }

    static func graphHeight(for width: CGFloat) -> CGFloat {
        7 * cellSide(for: width) + 6 * cellGap
    }

    static func hasVisibleData(_ history: CodexTokenHistory, now: Date = .now) -> Bool {
        history.days(now: now).suffix(weeks * 7).contains { !$0.isFuture && $0.tokens != nil }
    }

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
        let date = day.date.formatted(Date.FormatStyle(date: .complete, time: .omitted,
                                                      timeZone: CodexTokenHistory.calendar.timeZone))
        let heading = "\(day.isToday ? "Today · " : "")\(date) (UTC)"
        guard let tokens = day.tokens else { return "\(heading)\nNo record reported" }
        return "\(heading)\n\(tokens.formatted(.number.precision(.fractionLength(0)))) tokens"
    }
}

/// No fabricated readings: empty cells keep the connected heatmap's geometry.
struct CodexEmptyTokenHistoryView: View {
    let availableWidth: CGFloat

    var body: some View {
        let side = CodexTokenHistoryView.cellSide(for: availableWidth)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: CodexTokenHistoryView.cellGap) {
                ForEach(0..<CodexTokenHistoryView.weeks, id: \.self) { _ in
                    VStack(spacing: CodexTokenHistoryView.cellGap) {
                        ForEach(0..<7, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.overviewTrack)
                                .frame(width: side, height: side)
                        }
                    }
                }
            }
        }
        .frame(width: availableWidth, height: CodexTokenHistoryView.graphHeight(for: availableWidth), alignment: .leading)
        .help("Token activity · past 52 weeks\nNo data reported yet")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Token activity, no data yet")
    }
}
