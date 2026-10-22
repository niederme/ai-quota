import SwiftUI
import AIQuotaKit

/// Profile tokens, never the credit-spending history shown in service analytics.
struct CodexTokenHistoryView: View {
    private static let weeks = 42
    static let cellGap: CGFloat = 1
    private static let monthLabelWidth: CGFloat = 20
    private static let monthLabelSpacing: CGFloat = 4

    let history: CodexTokenHistory
    let availableWidth: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let days = Array(history.days().suffix(Self.weeks * 7))
        let positives = days.filter { !$0.isFuture }.compactMap(\.tokens).filter { $0 > 0 }.sorted()
        let side = Self.cellSide(for: availableWidth)
        let gridWidth = CGFloat(Self.weeks) * side + CGFloat(Self.weeks - 1) * Self.cellGap
        let visibleMonthWeeks = Self.visibleMonthWeeks(days, width: availableWidth)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: Self.cellGap) {
                ForEach(0..<Self.weeks, id: \.self) { week in
                    VStack(spacing: Self.cellGap) {
                        ForEach(0..<7, id: \.self) { row in
                            let day = days[week * 7 + row]
                            RoundedRectangle(cornerRadius: 1)
                                .fill(fill(day, sortedPositives: positives))
                                .frame(width: side, height: side)
                                .help(description(day))
                                .accessibilityLabel(day.isToday ? "Today, \(description(day))" : description(day))
                                .accessibilityHidden(day.isFuture)
                        }
                    }
                }
            }
            .frame(width: gridWidth, height: 7 * side + 6 * Self.cellGap, alignment: .topLeading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tokenActivityGrid")

            ZStack(alignment: .topLeading) {
                ForEach(visibleMonthWeeks, id: \.self) { week in
                    if let label = Self.monthLabel(days, week: week) {
                        Text(label)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .frame(width: Self.monthLabelWidth, alignment: .leading)
                            .offset(x: Self.monthLabelOffset(week: week, width: gridWidth))
                    }
                }
            }
            .frame(width: gridWidth, height: 12, alignment: .topLeading)
        }
        .frame(width: availableWidth, height: Self.graphHeight(for: availableWidth), alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Token activity, past 42 weeks")
        .accessibilityHint("Dim cells have no record. Dates are in UTC.")
        .accessibilityIdentifier("codexTokenActivity")
    }

    static func cellSide(for width: CGFloat) -> CGFloat {
        max(1, (width - CGFloat(weeks - 1) * cellGap) / CGFloat(weeks))
    }

    static func graphHeight(for width: CGFloat) -> CGFloat {
        7 * cellSide(for: width) + 6 * cellGap + 16
    }

    static func monthLabelOffset(week: Int, width: CGFloat) -> CGFloat {
        min(max(0, width - monthLabelWidth), CGFloat(week) * (cellSide(for: width) + cellGap))
    }

    static func visibleMonthWeeks(_ days: [CodexTokenHistory.Day], width: CGFloat) -> [Int] {
        let candidates: [(week: Int, x: CGFloat)] = (0..<weeks).compactMap { week in
            guard monthLabel(days, week: week) != nil else { return nil }
            return (week, monthLabelOffset(week: week, width: width))
        }
        guard let first = candidates.first, let last = candidates.last else { return [] }
        let minimumSpacing = monthLabelWidth + monthLabelSpacing
        var visible = [first.week]
        var lastX = first.x
        for candidate in candidates.dropFirst().dropLast() {
            guard candidate.x - lastX >= minimumSpacing,
                  last.x - candidate.x >= minimumSpacing else { continue }
            visible.append(candidate.week)
            lastX = candidate.x
        }
        if last.week != first.week, last.x - lastX >= minimumSpacing { visible.append(last.week) }
        return visible
    }

    static func hasVisibleData(_ history: CodexTokenHistory, now: Date = .now) -> Bool {
        history.days(now: now).suffix(weeks * 7).contains { !$0.isFuture && $0.tokens != nil }
    }

    private func fill(_ day: CodexTokenHistory.Day, sortedPositives: [Double]) -> Color {
        guard !day.isFuture else { return .clear }
        guard let tokens = day.tokens else { return Color.secondary.opacity(0.18) }
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
