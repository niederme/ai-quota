import SwiftUI
import Charts
import MobileAccessCore

/// Round 05's drill-down uses the daily-credit feed, never illustrative call counts.
struct CodexAnalyticsView: View {
    let reading: QuotaReading?
    let history: CodexUsageHistory?
    let historyUnavailable: Bool
    let busy: Bool
    let refresh: () -> Void
    @State private var period = 7
    @Environment(\.dynamicTypeSize) private var typeSize
    private var data: CodexHistoryPeriod { .init(history: history, count: period) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Usage period", selection: $period) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }.pickerStyle(.segmented).frame(maxWidth: 180)
                Text("Plan usage credits · not messages or extra charges.")
                    .font(.footnote).foregroundStyle(OverviewStyle.secondary)
            }
            if let history {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("History · " + overviewFreshnessLabel(history.fetchedAt, at: context.date, saved: historyUnavailable))
                        .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                }
            }
            if historyUnavailable || history == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Label(historyUnavailable ? "History couldn’t refresh" : busy ? "Loading history…" : "History not reported",
                          systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    if history != nil {
                        Text("Showing the last available history. Missing days stay empty.")
                            .font(.callout).foregroundStyle(OverviewStyle.secondary)
                    }
                    Button("Retry history", action: refresh).disabled(busy)
                }.modifier(AnalyticsCard())
            }
            if history != nil {
                CodexTrendCard(title: "Daily usage", data: data, breakdown: nil)
                CodexTrendCard(title: "By model", data: data, breakdown: .models)
                CodexTrendCard(title: "By app", data: data, breakdown: .surfaces)
            }
            if let spent = reading?.metadata?.usageSpent, spent > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Extra usage").font(.headline)
                    Text(spent.formatted(.currency(code: reading?.metadata?.usageCurrency ?? "USD")))
                        .font(.largeTitle.bold()).monospacedDigit()
                    Text("Beyond your subscription · " + (reading?.fetchedAt.formatted(.dateTime.month(.wide)) ?? "This month"))
                        .font(.callout).foregroundStyle(OverviewStyle.secondary)
                    Text("Converted at 25 credits = $1. Excludes your subscription price and credit purchases.")
                        .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                }.modifier(AnalyticsCard())
            }
        }.foregroundStyle(OverviewStyle.primary).tint(OverviewStyle.accent)
    }
}

struct AnalyticsCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(reduceTransparency ? Color(uiColor: .secondarySystemBackground)
                        : scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(OverviewStyle.primary.opacity(scheme == .dark ? 0.14 : 0.08)) }
    }
}

struct CodexTrendCard: View {
    let title: String
    let data: CodexHistoryPeriod
    let breakdown: CodexHistoryPeriod.Breakdown?
    var focusedID: String? = nil
    @State private var selection: Date?
    @State private var showDays = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var series: [CodexHistoryPeriod.Series] {
        breakdown.map { data.series($0) } ?? []
    }
    private var visibleSeries: [CodexHistoryPeriod.Series] {
        if let focusedID { return series.filter { $0.id == focusedID } }
        return Array(series.prefix(3))
    }
    private var total: Double {
        focusedID.flatMap { id in series.first { $0.id == id }?.total } ?? data.total
    }
    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return data.days.indices.min { a, b in
            abs((CodexHistoryPeriod.date(data.days[a].date) ?? .distantPast).timeIntervalSince(selection))
                < abs((CodexHistoryPeriod.date(data.days[b].date) ?? .distantPast).timeIntervalSince(selection))
        }
    }
    private struct Point: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let series: String
        let colorIndex: Int
    }
    private var points: [Point] {
        var result: [Point] = []
        let sources: [(String, [Double?])] = breakdown == nil
            ? [("Usage", data.days.map(\.credits))]
            : visibleSeries.map { ($0.id, $0.values) }
        for (colorIndex, source) in sources.enumerated() {
            var segment = 0
            for (index, day) in data.days.enumerated() {
                guard let value = source.1[index], let date = CodexHistoryPeriod.date(day.date) else {
                    segment += 1
                    continue
                }
                result.append(Point(id: source.0 + day.date, date: date, value: value,
                                    series: source.0 + "-\(segment)", colorIndex: colorIndex))
            }
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(OverviewStyle.secondary)
            if (breakdown == nil && data.reportedDays > 0) || !series.isEmpty {
                Text(total.formatted(.number.precision(.fractionLength(0...2))))
                    .font(.largeTitle.bold()).monospacedDigit()
                Text("usage credits" + (data.isPartial ? " · partial period" : ""))
                    .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                if let first = data.days.first, let last = data.days.last {
                    Text(Self.dateLabel(first.date) + " – " + Self.dateLabel(last.date))
                        .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                }
                chart
                if let index = selectedIndex {
                    selectedDay(index)
                } else {
                    Text("Tap a day to see its reported usage.")
                        .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                }
                if let breakdown, data.missingAttribution(breakdown) {
                    Text("Some reported usage has no \(breakdown == .models ? "model" : "app") attribution.")
                        .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                }
                if breakdown != nil && focusedID == nil {
                    ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                        NavigationLink {
                            ScrollView {
                                CodexTrendCard(title: Self.displayName(item.id), data: data,
                                               breakdown: breakdown, focusedID: item.id)
                                    .padding(20)
                            }.background { BrandSurfaceBackground().ignoresSafeArea() }
                                .navigationTitle(Self.displayName(item.id))
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            seriesRow(item, index: index)
                        }.buttonStyle(.plain)
                    }
                    if series.count > 3 {
                        Text("Chart shows the three leading series. All reported categories are listed.")
                            .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                    }
                }
                Button("View daily readings") { showDays.toggle() }
                    .font(.callout.weight(.semibold)).padding(.vertical, 4)
                if showDays {
                    ForEach(Array(data.days.enumerated()), id: \.element.id) { index, _ in
                        selectedDay(index)
                    }
                }
            } else {
                Text(breakdown == nil ? "Daily usage not reported for this period."
                     : "No \(breakdown == .models ? "model" : "app") breakdown reported for this period.")
                    .font(.callout).foregroundStyle(OverviewStyle.secondary)
            }
        }.modifier(AnalyticsCard())
            .onChange(of: data.days.map(\.date)) { _, _ in selection = nil }
    }
    private var chart: some View {
        Chart(points) { point in
            LineMark(x: .value("Date", point.date), y: .value("Usage credits", point.value),
                     series: .value("Reported segment", point.series))
                .foregroundStyle(Self.color(point.colorIndex))
                .lineStyle(StrokeStyle(lineWidth: 2))
            PointMark(x: .value("Date", point.date), y: .value("Usage credits", point.value))
                .foregroundStyle(Self.color(point.colorIndex)).symbolSize(12)
        }
        .chartYScale(domain: 0...max(1, points.map(\.value).max() ?? 1))
        .chartXScale(domain: dateDomain)
        .chartXAxis {
            AxisMarks(values: axisDates) {
                AxisValueLabel(format: Date.FormatStyle(timeZone: TimeZone(secondsFromGMT: 0)!).month(.abbreviated).day(), centered: false)
                    .font(.caption2)
            }
        }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
        .chartLegend(.hidden)
        .chartXSelection(value: $selection)
        .frame(height: typeSize.isAccessibilitySize ? 220 : 170)
        .accessibilityLabel(title + " trend")
        .accessibilityHint("Daily values are also available using View daily readings.")
    }
    private var axisDates: [Date] {
        let first = dateDomain.lowerBound, last = dateDomain.upperBound
        if typeSize.isAccessibilitySize { return [first, last] }
        return [first, first.addingTimeInterval(last.timeIntervalSince(first) / 2), last]
    }
    private var dateDomain: ClosedRange<Date> {
        let start = data.days.first.flatMap { CodexHistoryPeriod.date($0.date) } ?? .now
        let end = data.days.last.flatMap { CodexHistoryPeriod.date($0.date) } ?? start
        return start...max(start.addingTimeInterval(86400), end)
    }
    private func selectedDay(_ index: Int) -> some View {
        let day = data.days[index]
        let amount = focusedID.flatMap { id in series.first { $0.id == id }?.values[index] } ?? (focusedID == nil ? day.credits : nil)
        return VStack(alignment: .leading, spacing: 4) {
            Text(Self.dateLabel(day.date)).font(.callout.weight(.semibold))
            Text(amount.map { $0.formatted(.number.precision(.fractionLength(0...2))) + " usage credits" } ?? "Not reported")
                .font(.callout).foregroundStyle(OverviewStyle.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func seriesRow(_ item: CodexHistoryPeriod.Series, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(Self.color(index)).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(Self.displayName(item.id)).font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(OverviewStyle.secondary)
            }
            Text(item.total.formatted(.number.precision(.fractionLength(0...2))) + " credits · " +
                 (data.total > 0 ? (item.total / data.total).formatted(.percent.precision(.fractionLength(0))) + " of reported usage" : ""))
                .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .foregroundStyle(OverviewStyle.primary)
    }
    static func color(_ index: Int) -> Color {
        [OverviewStyle.accent, Color.orange, Color.green, Color.pink][index % 4]
    }
    static func dateLabel(_ string: String) -> String {
        CodexHistoryPeriod.date(string)?.formatted(Date.FormatStyle(timeZone: TimeZone(secondsFromGMT: 0)!).month(.abbreviated).day()) ?? string
    }
    static func displayName(_ name: String) -> String {
        ["cli": "CLI", "vscode": "VS Code", "desktop_app": "Desktop", "web": "Web",
         "mobile": "Mobile", "sdk": "SDK", "github_code_review": "GitHub review",
         "codex-auto-review": "Auto review"][name]
            ?? name.replacingOccurrences(of: "gpt-", with: "GPT-").replacingOccurrences(of: "_", with: " ")
    }
}

/// Allowance appears as reported progress rows, without repeating overview rings.
