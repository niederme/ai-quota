import SwiftUI
#if canImport(AIQuotaKit)
import AIQuotaKit
#endif

struct MacQuotaInsightBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    let forecast: QuotaExhaustionForecast
    let accountLabel: String
    var inset = true
    let onDismiss: () -> Void

    private var accent: Color {
        colorScheme == .dark ? Color(red: 0.749, green: 0.353, blue: 0.949)
            : Color(red: 0.686, green: 0.322, blue: 0.871)
    }
    private var primary: Color {
        colorScheme == .dark ? .white : Color(red: 0.043137, green: 0.023529, blue: 0.058824)
    }
    private var rangeText: String {
        QuotaForecastTextFormatter.range(forecast)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(accountLabel) may reach its \(forecast.scope.window.label) limit around \(rangeText)")
                    .font(.system(size: 15, weight: .semibold))
                Text("At your recent pace · Resets \(QuotaForecastTextFormatter.reset(forecast))")
                    .font(.system(size: 15))
            }
            .foregroundStyle(primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor).opacity(0.75))
                    .frame(width: 28, height: 28, alignment: .topTrailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss for this account’s quota window")
            .accessibilityLabel("Dismiss quota insight for \(accountLabel)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.regularMaterial)
                .overlay { RoundedRectangle(cornerRadius: 24).fill(accent.opacity(0.14)) }
                .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.primary.opacity(0.16), lineWidth: 1) }
        }
        .padding(.horizontal, inset ? 16 : 0)
        .padding(.vertical, inset ? 8 : 0)
        .help("Approximate range from this account’s recent quota observations. Changes in usage can change the estimate.")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quotaPaceInsight")
    }
}
