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
        guard let tokens = day.tokens, tokens != 0 else { return tokenHistoryRestingFill(colorScheme) }
        // Active-day colors retain the existing platform-matched intensity ramp.
        let colors: [Color] = colorScheme == .dark ? [
            Color(red: 0x60 / 255.0, green: 0x3C / 255.0, blue: 0x79 / 255.0),
            Color(red: 0x7A / 255.0, green: 0x48 / 255.0, blue: 0x9A / 255.0),
            Color(red: 0x9C / 255.0, green: 0x58 / 255.0, blue: 0xC2 / 255.0),
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

// Missing and reported-zero days share a quiet purple fill. Their data and
// accessible descriptions remain distinct; opaque fills read over tinted cards.
private func tokenHistoryRestingFill(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
        ? Color(red: 0x53 / 255.0, green: 0x3A / 255.0, blue: 0x72 / 255.0)
        : Color(red: 0xCD / 255.0, green: 0xB5 / 255.0, blue: 0xE3 / 255.0)
}

/// No fabricated readings: empty cells keep the connected heatmap's geometry.
struct CodexEmptyTokenHistoryView: View {
    let availableWidth: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let side = CodexTokenHistoryView.cellSide(for: availableWidth)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: CodexTokenHistoryView.cellGap) {
                ForEach(0..<CodexTokenHistoryView.weeks, id: \.self) { _ in
                    VStack(spacing: CodexTokenHistoryView.cellGap) {
                        ForEach(0..<7, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(tokenHistoryRestingFill(colorScheme))
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
