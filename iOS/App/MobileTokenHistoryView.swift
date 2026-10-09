import SwiftUI
import MobileAccessCore

/// Profile tokens, never the credit-spending history shown in service analytics.
struct MobileTokenHistoryView: View {
    let history: CodexTokenHistory?
    let unavailable: Bool
    let loading: Bool
    var retry: (() -> Void)? = nil
    @State private var selected: CodexTokenHistory.Day?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Token activity").font(.subheadline.weight(.semibold))
                Spacer()
                Text("52 weeks").font(.caption).foregroundStyle(.secondary)
            }
            if let history {
                let days = history.days()
                let positives = days.filter { !$0.isFuture }.compactMap(\.tokens).filter { $0 > 0 }.sorted()
                let ceiling = positives.isEmpty ? 1 : positives[min(positives.count - 1, Int(Double(positives.count - 1) * 0.95))]
                GeometryReader { geometry in
                    let gap = 1.0
                    let side = max(1, (geometry.size.width - 51 * gap) / 52)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: gap) {
                            ForEach(0..<52, id: \.self) { week in
                                VStack(spacing: gap) {
                                    ForEach(0..<7, id: \.self) { row in
                                        let day = days[week * 7 + row]
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(fill(day, ceiling: ceiling))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 1)
                                                    .strokeBorder(day.isToday ? Color.primary : Color.secondary.opacity(day.tokens == nil ? 0.35 : 0), lineWidth: day.isToday ? 1 : 0.5)
                                                    .opacity(day.isFuture ? 0 : 1)
                                            }
                                            .frame(width: side, height: side)
                                            .accessibilityLabel(description(day))
                                            .accessibilityHidden(day.isFuture)
                                            .accessibilityAddTraits(.isButton)
                                            .accessibilityAction { selected = day }
                                    }
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            let week = min(51, max(0, Int(value.location.x / (side + gap))))
                            let row = min(6, max(0, Int(value.location.y / (side + gap))))
                            let day = days[week * 7 + row]
                            if !day.isFuture { selected = day }
                        })
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("tokenActivityGrid")
                        ZStack(alignment: .topLeading) {
                            ForEach(0..<52, id: \.self) { week in
                                if let label = monthLabel(days, week: week) {
                                    Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
                                        .frame(width: 18, alignment: week >= 49 ? .trailing : .leading)
                                        .offset(x: min(geometry.size.width - 18, CGFloat(week) * (side + gap)))
                                }
                            }
                        }.frame(height: 12)
                    }
                }
                .aspectRatio(52.0 / 10.0, contentMode: .fit)
                Text(selected.map(description) ?? "Outlined: no record · dates in UTC")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tokenActivityDetail")
                if unavailable {
                    HStack {
                        Text("Saved token history · refresh unavailable").font(.caption2).foregroundStyle(.secondary)
                        if let retry { Button("Retry", action: retry).font(.caption) }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    if loading { ProgressView().controlSize(.small) }
                    Text(loading ? "Loading token history…" : "Token history unavailable for this account")
                        .font(.caption).foregroundStyle(.secondary)
                    if unavailable, !loading, let retry { Button("Retry", action: retry).font(.caption) }
                }.frame(minHeight: 54)
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: history?.fetchedAt) { _, _ in selected = nil }
    }
    private func fill(_ day: CodexTokenHistory.Day, ceiling: Double) -> Color {
        guard !day.isFuture, let tokens = day.tokens else { return .clear }
        if tokens == 0 { return Color.secondary.opacity(colorScheme == .dark ? 0.18 : 0.12) }
        let fraction = tokens / max(1, ceiling)
        let opacity = fraction < 0.25 ? 0.25 : fraction < 0.5 ? 0.43 : fraction < 0.75 ? 0.65 : 1
        return Color(red: 0.69, green: 0.32, blue: 0.91).opacity(opacity)
    }
    private func description(_ day: CodexTokenHistory.Day) -> String {
        guard let tokens = day.tokens else { return "\(day.key): no record reported" }
        return "\(day.key): \(tokens.formatted(.number.precision(.fractionLength(0)))) tokens"
    }
    private func monthLabel(_ days: [CodexTokenHistory.Day], week: Int) -> String? {
        guard let day = days[(week * 7)..<(week * 7 + 7)].first(where: {
            !$0.isFuture && CodexTokenHistory.calendar.component(.day, from: $0.date) == 1
        }) else { return nil }
        let formatter = CodexTokenHistory.dateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: day.date)
    }
}
