import SwiftUI
#if canImport(AIQuotaKit)
import AIQuotaKit
#endif

struct MacQuotaInsightBanner: View {
    let forecast: QuotaExhaustionForecast
    let accountLabel: String
    var bankedResets: CodexBankedResetContext? = nil
    var inset = true
    var indentsForecast = false
    var separatesAccountName = true
    let onDismiss: () -> Void

    private var row: some View {
        MacAlertRow(title: separatesAccountName ? accountLabel : QuotaForecastTextFormatter.title(forecast, accountLabel: accountLabel),
                    announcement: false, indentsForecast: indentsForecast, onDismiss: onDismiss) {
            if separatesAccountName {
                Text(QuotaForecastTextFormatter.sentence(forecast))
                    .fontWeight(.semibold).foregroundStyle(Color.overviewPrimary)
            }
            Text(QuotaForecastTextFormatter.detail(forecast, bankedResets: bankedResets))
        }
        .help("Estimate from current quota usage and available service history. Changes in usage can change the forecast.")
        .accessibilityLabel(QuotaForecastTextFormatter.accessibilitySummary(forecast, accountLabel: accountLabel, bankedResets: bankedResets))
        .accessibilityHint(bankedResets?.availableCount(for: forecast, now: .now) != nil
            ? "Banked resets require separate action in Codex. The time shown is the scheduled refresh." : "")
        .accessibilityIdentifier("quotaPaceInsight")
    }

    var body: some View {
        if inset {
            MacAlertGroup { row }.padding(.horizontal, 16).padding(.vertical, 8)
        } else {
            row
        }
    }
}
