import SwiftUI
import MobileAccessCore

/// Profile tokens, never the credit-spending history shown in service analytics.
struct MobileTokenHistoryView: View {
    let history: CodexTokenHistory?
    let unavailable: Bool
    let loading: Bool
    var availableWidth: CGFloat = 288
    var retry: (() -> Void)? = nil
    @State private var selected: CodexTokenHistory.Day?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var skeletonBright = false

    enum Presentation: Equatable { case loading, empty, unavailable, populated }
    static func presentation(history: CodexTokenHistory?, unavailable: Bool, loading: Bool, now: Date = .now) -> Presentation {
        if let history {
            return history.days(now: now).contains { !$0.isFuture && $0.tokens != nil } ? .populated : .empty
        }
        return loading ? .loading : .unavailable
    }
    private var presentation: Presentation { Self.presentation(history: history, unavailable: unavailable, loading: loading) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Token activity").font(.subheadline.weight(.semibold))
                Spacer()
                Text("52 weeks").font(.caption).foregroundStyle(.secondary)
            }
            if let history, presentation == .populated {
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
                .frame(height: graphHeight)
                Text(selected.map(description) ?? "Outlined: no record · dates in UTC")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tokenActivityDetail")
            } else {
                ZStack {
                    if presentation == .loading {
                        skeleton
                    } else {
                        VStack(spacing: 4) {
                            Text(presentation == .empty ? "No token history yet" : "Token history unavailable")
                                .font(.caption.weight(.medium))
                            Text(presentation == .empty ? "No daily records in the past 52 weeks." : "Couldn’t retrieve daily records for this account.")
                                .font(.caption2).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }.padding(.horizontal, 8)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: graphHeight)
                .accessibilityIdentifier("tokenActivityPlaceholder")
                Text(presentation == .loading ? "Loading token history…" : "No record does not mean zero tokens.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("tokenActivityDetail")
            }
            if unavailable || loading && history != nil {
                HStack(spacing: 8) {
                    Text(loading ? "Updating token history…" : history != nil ? "Saved token history · refresh unavailable" : "Try refreshing your token history.")
                        .font(.caption2).foregroundStyle(.secondary)
                    if unavailable, !loading, let retry { Button("Retry", action: retry).font(.caption) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: history?.fetchedAt) { _, _ in selected = nil }
    }
    private var graphHeight: CGFloat { max(64, availableWidth * 10 / 52) }
    private var skeleton: some View {
        GeometryReader { geometry in
            let gap = 1.0
            let side = max(1, (geometry.size.width - 51 * gap) / 52)
            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<52, id: \.self) { _ in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.secondary.opacity(skeletonBright ? 0.20 : 0.10))
                                .frame(width: side, height: side)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { skeletonBright = true }
        }
        .onDisappear { skeletonBright = false }
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
