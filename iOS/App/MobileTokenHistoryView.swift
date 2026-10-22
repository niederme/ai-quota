import SwiftUI
import MobileAccessCore

/// Profile tokens, never the credit-spending history shown in service analytics.
struct MobileTokenHistoryView: View {
    private static let weeks = CodexTokenHistory.visibleWeeks
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
                let gap = 1.0
                let side = max(1, (geometry.size.width - CGFloat(Self.weeks - 1) * gap) / CGFloat(Self.weeks))
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
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<Self.weeks, id: \.self) { week in
                            if let label = Self.monthLabel(days, week: week) {
                                Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
                                    .frame(width: 32, alignment: week == Self.weeks - 1 ? .trailing : .leading)
                                    .offset(x: min(geometry.size.width - 32, CGFloat(week) * (side + gap)))
                            }
                        }
                    }.frame(height: 12)
                }
            }
            .frame(height: graphHeight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Token activity, past 13 weeks")
            .accessibilityHint("Outlined cells have no record. Dates are in UTC.")
        }
    }
    private var graphHeight: CGFloat {
        let side = max(1, (availableWidth - CGFloat(Self.weeks - 1)) / CGFloat(Self.weeks))
        return 7 * side + 6 + 16
    }
    private func fill(_ day: CodexTokenHistory.Day, sortedPositives: [Double]) -> Color {
        guard !day.isFuture, let tokens = day.tokens else { return .clear }
        if tokens == 0 { return Color.secondary.opacity(colorScheme == .dark ? 0.18 : 0.12) }
        let rank = Double(sortedPositives.filter { $0 <= tokens }.count) / Double(sortedPositives.count)
        let opacity = Self.positiveOpacity(fraction: rank)
        return Color(red: 0.69, green: 0.32, blue: 0.91).opacity(opacity)
    }
    static func positiveOpacity(fraction: Double) -> Double {
        if fraction < 0.2 { return 0.35 }
        if fraction < 0.4 { return 0.52 }
        if fraction < 0.6 { return 0.69 }
        if fraction < 0.8 { return 0.84 }
        return 1
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
