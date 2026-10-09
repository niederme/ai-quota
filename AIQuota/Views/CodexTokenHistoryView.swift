import SwiftUI
import AIQuotaKit

struct CodexTokenHistoryView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var selected: CodexTokenHistory.Day?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Token activity").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("52 weeks").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let history = viewModel.codexTokenHistory {
                let days = history.days()
                let positives = days.filter { !$0.isFuture }.compactMap(\.tokens).filter { $0 > 0 }.sorted()
                let ceiling = positives.isEmpty ? 1 : positives[min(positives.count - 1, Int(Double(positives.count - 1) * 0.95))]
                GeometryReader { geometry in
                    let side = max(1, (geometry.size.width - 51 * 1.2) / 52)
                    HStack(alignment: .top, spacing: 1.2) {
                        ForEach(0..<52, id: \.self) { week in
                            VStack(spacing: 1.2) {
                                ForEach(0..<7, id: \.self) { row in
                                    let day = days[week * 7 + row]
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
                                        .onHover { hovering in selected = hovering && !day.isFuture ? day : nil }
                                        .onTapGesture { if !day.isFuture { selected = day } }
                                }
                            }
                        }
                    }
                }
                .frame(height: 44)
                GeometryReader { geometry in
                    let stride = geometry.size.width / 52
                    ForEach(0..<52, id: \.self) { week in
                        if let label = monthLabel(days: days, week: week) {
                            Text(label)
                                .font(.system(size: 8.5)).foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .leading)
                                .offset(x: min(geometry.size.width - 20, CGFloat(week) * stride))
                        }
                    }
                }.frame(height: 11)
                Text(selected.map(description) ?? (viewModel.tokenHistoryFailed ? "Saved history · refresh unavailable" : "Outlined: no record · dates in UTC"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                HStack(spacing: 6) {
                    if viewModel.isTokenHistoryLoading { ProgressView().controlSize(.mini) }
                    Text(viewModel.isTokenHistoryLoading ? "Loading token history…" : viewModel.tokenHistoryFailed ? "Token history could not be loaded" : "Token history unavailable for this account")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if viewModel.tokenHistoryFailed {
                        Button("Retry") { viewModel.refreshTokenHistory(force: true) }.font(.system(size: 11))
                    }
                }.frame(minHeight: 44)
            }
        }
        .task { viewModel.refreshTokenHistory() }
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
