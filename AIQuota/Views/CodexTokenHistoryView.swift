import SwiftUI
import AIQuotaKit

struct CodexTokenHistoryView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let history = viewModel.codexTokenHistory, history.days().contains(where: { !$0.isFuture && $0.tokens != nil }) {
                let days = history.days()
                let positives = days.filter { !$0.isFuture }.compactMap(\.tokens).filter { $0 > 0 }.sorted()
                let ceiling = positives.isEmpty ? 1 : positives[min(positives.count - 1, Int(Double(positives.count - 1) * 0.95))]
                GeometryReader { geometry in
                    let weekCount = min(52, max(1, Int(((geometry.size.width + cellGap) / (cellSide + cellGap)).rounded())))
                    let recentDays = Array(days.suffix(weekCount * 7))
                    let side = max(1, (geometry.size.width - CGFloat(weekCount - 1) * cellGap) / CGFloat(weekCount))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: cellGap) {
                            ForEach(0..<weekCount, id: \.self) { week in
                                VStack(spacing: cellGap) {
                                    ForEach(0..<7, id: \.self) { row in
                                        let day = recentDays[week * 7 + row]
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(fill(day, ceiling: ceiling))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 1)
                                                    .strokeBorder(day.isToday ? Color.primary : Color.secondary.opacity(day.tokens == nil ? 0.3 : 0), lineWidth: day.isToday ? 1 : 0.65)
                                                    .opacity(day.isFuture ? 0 : 1)
                                            }
                                            .frame(width: side, height: side)
                                            .help(description(day))
                                            .accessibilityLabel(description(day))
                                            .accessibilityHidden(day.isFuture)
                                    }
                                }
                            }
                        }
                        ZStack(alignment: .topLeading) {
                            ForEach(monthLabels(days: recentDays, width: geometry.size.width, step: side + cellGap), id: \.week) { label in
                                Text(label.text)
                                    .font(.system(size: 8.5)).foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .leading)
                                    .offset(x: label.x)
                            }
                        }
                        .frame(width: geometry.size.width, height: 11, alignment: .topLeading)
                    }
                }
                .frame(height: 59)
                if viewModel.tokenHistoryFailed {
                    Text("Saved history · refresh unavailable")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 6) {
                    if viewModel.isTokenHistoryLoading { ProgressView().controlSize(.mini) }
                    Text(viewModel.codexTokenHistory != nil ? "No token history yet" : viewModel.isTokenHistoryLoading ? "Loading token history…" : viewModel.tokenHistoryFailed ? "Token history could not be loaded" : "Token history unavailable for this account")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if viewModel.tokenHistoryFailed {
                        Button("Retry") { viewModel.refreshTokenHistory(force: true) }.font(.system(size: 11))
                    }
                }.frame(minHeight: 59)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Codex token activity, recent daily history")
        .help("Recent daily Codex token counts from your ChatGPT profile. Outlined cells have no reported record; muted cells are confirmed zero. Dates are in UTC.")
        .accessibilityIdentifier("codexTokenActivity")
        .task { viewModel.refreshTokenHistory() }
    }

    private let cellSide: CGFloat = 5.2
    private let cellGap: CGFloat = 1.2
    private func monthLabels(days: [CodexTokenHistory.Day], width: CGFloat, step: CGFloat) -> [(week: Int, text: String, x: CGFloat)] {
        let candidates = (0..<(days.count / 7)).compactMap { week -> (week: Int, text: String, x: CGFloat)? in
            guard let text = monthLabel(days: days, week: week) else { return nil }
            return (week, text, min(width - 20, CGFloat(week) * step))
        }
        var labels: [(week: Int, text: String, x: CGFloat)] = []
        for candidate in candidates {
            if labels.last.map({ candidate.x - $0.x >= 40 }) ?? true { labels.append(candidate) }
        }
        // Keep the current month for orientation, omitting a crowded neighbor.
        if let last = candidates.last, labels.last?.week != last.week {
            if let previous = labels.last, last.x - previous.x < 40 { labels.removeLast() }
            labels.append(last)
        }
        return labels
    }

    private func monthLabel(days: [CodexTokenHistory.Day], week: Int) -> String? {
        guard let first = days[(week * 7)..<(week * 7 + 7)].first(where: {
            !$0.isFuture && CodexTokenHistory.calendar.component(.day, from: $0.date) == 1
        }) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = CodexTokenHistory.calendar
        formatter.timeZone = CodexTokenHistory.calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter.string(from: first.date)
    }

    private func fill(_ day: CodexTokenHistory.Day, ceiling: Double) -> Color {
        guard !day.isFuture, let tokens = day.tokens else { return .clear }
        guard tokens > 0 else { return Color.secondary.opacity(colorScheme == .dark ? 0.18 : 0.12) }
        let fraction = tokens / max(1, ceiling)
        let opacity = fraction < 0.25 ? 0.25 : fraction < 0.5 ? 0.43 : fraction < 0.75 ? 0.65 : 1.0
        return Color.gaugeAccent.opacity(opacity)
    }

    private func description(_ day: CodexTokenHistory.Day) -> String {
        if day.isFuture { return "\(day.key): future date" }
        guard let tokens = day.tokens else { return "\(day.key): no record reported" }
        return "\(day.key): \(tokens.formatted(.number.precision(.fractionLength(0)))) tokens"
    }
}
