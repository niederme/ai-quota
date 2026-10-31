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
            Text("Around \(QuotaForecastTextFormatter.range(forecast)) at your recent pace · Resets \(QuotaForecastTextFormatter.reset(forecast))")
        }
        .help("Approximate range from this account’s recent quota observations. Changes in usage can change the estimate.")
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
