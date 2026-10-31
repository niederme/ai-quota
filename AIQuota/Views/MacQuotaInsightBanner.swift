import SwiftUI
#if canImport(AIQuotaKit)
import AIQuotaKit
#endif

struct MacQuotaInsightBanner: View {
    let forecast: QuotaExhaustionForecast
    let accountLabel: String
    var inset = true
    let onDismiss: () -> Void

    private var row: some View {
        MacAlertRow(title: "\(accountLabel) may hit its \(forecast.scope.window.label) limit",
                    announcement: false, onDismiss: onDismiss) {
            Text(QuotaForecastTextFormatter.detail(forecast))
        }
        .help("Estimate from current quota usage and available service history. Changes in usage can change the forecast.")
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
