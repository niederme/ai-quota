import SwiftUI
import MobileAccessCore

/// Devin's service detail: daily and weekly quota windows plus plan and
/// on-demand balance metadata, rendered from the shared QuotaReading.
struct DevinAnalyticsView: View {
    let reading: QuotaReading?
    let busy: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            windowCard(title: "Daily quota", window: reading?.shortTerm)
            windowCard(title: "Weekly quota", window: reading?.weekly)

            if reading?.metadata != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Account").font(.headline)
                    if let plan = reading?.metadata?.plan {
                        labelledRow("Plan", plan)
                    }
                    if let balance = reading?.metadata?.balanceUSD {
                        labelledRow("On-demand balance", balance.formatted(.currency(code: "USD")))
                    }
                    if let fetchedAt = reading?.fetchedAt {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text("Reported " + analyticsFreshnessLabel(fetchedAt, at: context.date, saved: false))
                                .font(.footnote).foregroundStyle(AnalyticsStyle.secondary)
                        }
                    }
                }.modifier(AnalyticsCard())
            }
        }.foregroundStyle(AnalyticsStyle.primary).tint(AnalyticsStyle.accent)
    }

    private func windowCard(title: String, window: QuotaWindow?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if let window {
                Text(window.usedPercent.formatted(.number.precision(.fractionLength(0...1))) + "%")
                    .font(.largeTitle.bold()).monospacedDigit()
                Text("used").font(.callout).foregroundStyle(AnalyticsStyle.secondary)
                if let resetsAt = window.resetsAt {
                    Text(resetsAt > .now
                         ? "Resets " + resetsAt.formatted(.relative(presentation: .named))
                         : "Reset pending")
                        .font(.callout).foregroundStyle(AnalyticsStyle.secondary)
                }
            } else {
                Text("Not reported")
                    .font(.callout).foregroundStyle(AnalyticsStyle.secondary)
            }
        }.modifier(AnalyticsCard())
    }

    private func labelledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(AnalyticsStyle.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }.font(.callout)
    }
}
