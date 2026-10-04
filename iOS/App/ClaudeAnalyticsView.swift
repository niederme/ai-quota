import SwiftUI
import MobileAccessCore

struct ClaudeAnalyticsView: View {
    let reading: QuotaReading?
    let busy: Bool
    let failed: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Analytics").font(.title2.bold())
            VStack(alignment: .leading, spacing: 12) {
                Text("This week by product").font(.headline)
                if let breakdown = reading?.claudeBreakdown {
                    ForEach(breakdown.rows) { row in
                        NavigationLink {
                            ClaudeProductDetail(row: row, breakdown: breakdown, failed: failed)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.displayName).font(.body.weight(.semibold))
                                    Spacer(minLength: 8)
                                    Text(row.percent.formatted(.number.precision(.fractionLength(0...1))) + "%")
                                        .font(.body.bold()).monospacedDigit().layoutPriority(1)
                                    Image(systemName: "chevron.right").font(.caption)
                                        .foregroundStyle(OverviewStyle.secondary)
                                }
                                ProgressView(value: row.percent, total: 100).tint(OverviewStyle.accent)
                                    .accessibilityHidden(true)
                            }.padding(.vertical, 6).frame(minHeight: 44)
                        }.buttonStyle(.plain)
                    }
                    ClaudeBreakdownFreshness(breakdown: breakdown, failed: failed)
                    Text("Percentages reported by Claude, separate from your allowance.")
                        .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                    if failed {
                        Text("Couldn’t refresh product details. Last reported values remain visible.")
                            .font(.callout).foregroundStyle(OverviewStyle.warning)
                        Button("Try again", action: refresh).disabled(busy)
                    }
                } else {
                    Text(busy ? "Fetching weekly breakdown…" : "Weekly breakdown unavailable")
                        .font(.callout.weight(.semibold))
                    Text("Product details appear when Claude reports them. Allowance is shown separately above.")
                        .font(.callout).foregroundStyle(OverviewStyle.secondary)
                    if !busy { Button("Try again", action: refresh) }
                }
            }.modifier(AnalyticsCard())
            if let spent = reading?.metadata?.usageSpent, spent > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Extra usage").font(.headline)
                    Text(reading?.metadata?.usageCurrency.flatMap { $0.isEmpty ? nil : $0 }
                        .map { spent.formatted(.currency(code: $0)) }
                        ?? spent.formatted(.number.precision(.fractionLength(0...2))) + " credits")
                        .font(.largeTitle.bold()).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Outside your plan allowance. Your subscription price is separate.")
                        .font(.callout).foregroundStyle(OverviewStyle.secondary)
                }.modifier(AnalyticsCard())
            } else if reading?.metadata?.usageSpent == nil {
                Text("Spending not reported").font(.callout).foregroundStyle(OverviewStyle.secondary)
            }
        }.foregroundStyle(OverviewStyle.primary).tint(OverviewStyle.accent)
    }
}

struct ClaudeBreakdownFreshness: View {
    let breakdown: ClaudeWeeklyBreakdown
    let failed: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text("Products · " + overviewFreshnessLabel(breakdown.asOf, at: context.date, saved: failed))
                Text("Reported as of " + breakdown.asOf.formatted(date: .abbreviated, time: .shortened))
                Text("Window started " + breakdown.windowStartedAt.formatted(date: .abbreviated, time: .shortened))
            }.font(.footnote).foregroundStyle(OverviewStyle.secondary)
        }
    }
}

struct ClaudeProductDetail: View {
    let row: ClaudeWeeklyBreakdown.Row
    let breakdown: ClaudeWeeklyBreakdown
    let failed: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reported product percentage").font(.headline)
                Text(row.percent.formatted(.number.precision(.fractionLength(0...1))) + "%")
                    .font(.largeTitle.bold()).monospacedDigit()
                Text(row.displayName).font(.title2.bold())
                ClaudeBreakdownFreshness(breakdown: breakdown, failed: failed)
                Text("This is the percentage Claude reported for this product. It is separate from your allowance.")
                    .font(.callout).foregroundStyle(OverviewStyle.secondary)
            }.foregroundStyle(OverviewStyle.primary).modifier(AnalyticsCard()).padding(20)
        }.background { BrandSurfaceBackground().ignoresSafeArea() }
            .navigationTitle(row.displayName).navigationBarTitleDisplayMode(.inline)
    }
}
