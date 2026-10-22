import SwiftUI
import MobileAccessCore

/// Profile tokens, never the credit-spending history shown in service analytics.
struct MobileTokenHistoryView: View {
    private static let weeks = CodexTokenHistory.visibleWeeks
    static let cellGap: CGFloat = 1.5
    let history: CodexTokenHistory?
    let unavailable: Bool
    let loading: Bool
    var availableWidth: CGFloat = 288
    @Environment(\.colorScheme) private var colorScheme

    enum Presentation: Equatable { case loading, empty, unavailable, populated }
    static func presentation(history: CodexTokenHistory?, unavailable: Bool, loading: Bool, now: Date = .now) -> Presentation {
        if let history {
            return history.days(now: now).contains { !$0.isFuture && $0.tokens != nil } ? .populated : .empty
        }
        return loading ? .loading : .unavailable
    }
    private var presentation: Presentation { Self.presentation(history: history, unavailable: unavailable, loading: loading) }

    var body: some View {
        if let history, presentation == .populated {
            let days = history.days()
            let positives = days.filter { !$0.isFuture }.compactMap(\.tokens).filter { $0 > 0 }.sorted()
            GeometryReader { geometry in
                let gap = Self.cellGap
                let side = Self.cellSide(for: geometry.size.width)
                let cellHeight = Self.cellHeight(for: geometry.size.width)
                let gridWidth = CGFloat(Self.weeks) * side + CGFloat(Self.weeks - 1) * gap
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(0..<Self.weeks, id: \.self) { week in
                            VStack(spacing: gap) {
                                ForEach(0..<7, id: \.self) { row in
                                    let day = days[week * 7 + row]
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(fill(day, sortedPositives: positives))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 1)
                                                .strokeBorder(Color.secondary.opacity(day.tokens == nil ? 0.35 : 0), lineWidth: 0.5)
                                                .opacity(day.isFuture ? 0 : 1)
                                        }
                                        .frame(width: side, height: cellHeight)
                                        .accessibilityLabel(day.isToday ? "Today, \(description(day))" : description(day))
                                        .accessibilityHidden(day.isFuture)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 44, alignment: .top)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("tokenActivityGrid")
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<Self.weeks, id: \.self) { week in
                            if let label = Self.monthLabel(days, week: week) {
                                Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .leading)
                                    .offset(x: min(gridWidth - 20, CGFloat(week) * (side + gap)))
                            }
                        }
                    }.frame(height: 12)
                }
            }
            .frame(height: graphHeight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Token activity, past 26 weeks")
            .accessibilityHint("Outlined cells have no record. Dates are in UTC.")
        }
    }
    static func cellSide(for width: CGFloat) -> CGFloat {
        max(1, (width - CGFloat(weeks - 1) * cellGap) / CGFloat(weeks))
    }
    static func cellHeight(for width: CGFloat) -> CGFloat {
        cellSide(for: width) * 2 / 3
    }
    static func graphHeight(for width: CGFloat) -> CGFloat {
        max(44, 7 * cellHeight(for: width) + 6 * cellGap) + 16
    }
    private var graphHeight: CGFloat { Self.graphHeight(for: availableWidth) }
    private func fill(_ day: CodexTokenHistory.Day, sortedPositives: [Double]) -> Color {
        guard !day.isFuture, let tokens = day.tokens else { return .clear }
        if tokens == 0 {
            return colorScheme == .dark
                ? Color(red: 0.30, green: 0.28, blue: 0.34)
                : Color(red: 0.87, green: 0.85, blue: 0.90)
        }
        let rank = Double(sortedPositives.filter { $0 <= tokens }.count) / Double(max(1, sortedPositives.count))
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
        return colors[Self.positiveLevel(fraction: rank)]
    }
    // Quartiles keep a single unusually busy day from washing out the rest.
    static func positiveLevel(fraction: Double) -> Int {
        if fraction <= 0.25 { return 0 }
        if fraction <= 0.50 { return 1 }
        if fraction <= 0.75 { return 2 }
        return 3
    }
    private func description(_ day: CodexTokenHistory.Day) -> String {
        guard let tokens = day.tokens else { return "\(day.key): no record reported" }
        return "\(day.key): \(tokens.formatted(.number.precision(.fractionLength(0)))) tokens"
    }
    static func monthLabel(_ days: [CodexTokenHistory.Day], week: Int) -> String? {
        let firstOfMonth = days[(week * 7)..<(week * 7 + 7)].first(where: {
            !$0.isFuture && CodexTokenHistory.calendar.component(.day, from: $0.date) == 1
        })
        guard let day = firstOfMonth ?? (week == 0 ? days[0] : nil) else { return nil }
        let formatter = CodexTokenHistory.dateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: day.date)
    }
}
