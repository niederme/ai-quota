import SwiftUI
import MobileAccessCore

/// Devin's service detail: daily and weekly quota windows plus plan and
/// on-demand balance metadata from GetUserStatus.
struct DevinAnalyticsView: View {
    let usage: DevinUsage?
    let busy: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            windowCard(
                title: "Daily quota",
                usedPercent: usage?.dailyUsedPercent,
                resetsAt: usage?.dailyResetsAt
            )
            windowCard(
                title: "Weekly quota",
                usedPercent: usage?.weeklyUsedPercent,
                resetsAt: usage?.weeklyResetsAt
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Account").font(.headline)
                if let plan = usage?.planName {
                    labelledRow("Plan", plan)
                }
                if let name = usage?.accountDisplayName {
                    labelledRow("Account", name)
                }
                if let balance = usage?.overageBalanceUSD {
                    labelledRow("On-demand balance", balance.formatted(.currency(code: "USD")))
                }
                if let start = usage?.planStart, let end = usage?.planEnd {
                    labelledRow(
                        "Plan period",
                        "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
                    )
                }
                if let fetchedAt = usage?.fetchedAt {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text("Reported " + analyticsFreshnessLabel(fetchedAt, at: context.date, saved: false))
                            .font(.footnote).foregroundStyle(AnalyticsStyle.secondary)
                    }
                }
            }.modifier(AnalyticsCard())
        }.foregroundStyle(AnalyticsStyle.primary).tint(AnalyticsStyle.accent)
    }

    private func windowCard(title: String, usedPercent: Double?, resetsAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if let usedPercent {
                Text(usedPercent.formatted(.number.precision(.fractionLength(0...1))) + "%")
                    .font(.largeTitle.bold()).monospacedDigit()
                Text("used").font(.callout).foregroundStyle(AnalyticsStyle.secondary)
                if let resetsAt {
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
