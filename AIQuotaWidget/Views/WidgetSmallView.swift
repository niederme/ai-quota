import SwiftUI
import AIQuotaKit

struct WidgetSmallView: View {
    let entry: QuotaEntry

    private var pct: Int { entry.usage?.weeklyUsedPercent ?? 0 }
    private var fraction: Double { entry.usage?.weeklyPercentFraction ?? 0 }
    private var limitReached: Bool { entry.usage?.limitReached ?? false }

    private var tintColor: Color {
        if limitReached { return .red }
        switch pct {
        case ..<60: return .green
        case ..<85: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Label("Codex", systemImage: limitReached ? "exclamationmark.octagon.fill" : "brain.fill")
                .font(.caption2.bold())
                .foregroundStyle(limitReached ? .red : .purple)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            if let usage = entry.usage {
                // Gauge + percentage centered
                VStack(spacing: 3) {
                    Image(nsImage: GaugeImageMaker.image(
                        usedPercent: pct,
                        limitReached: limitReached,
                        isLoading: false,
                        size: 40
                    ))
                    .frame(width: 40, height: 40)

                    Text("\(pct)%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .foregroundStyle(tintColor)
                }
                .frame(maxWidth: .infinity)

                Spacer()

                // Footer
                VStack(alignment: .leading, spacing: 2) {
                    if limitReached {
                        Text("Limit reached")
                            .font(.caption2.bold())
                            .foregroundStyle(.red)
                    } else {
                        Text("\(usage.weeklyRemaining)% remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(countdownText(seconds: usage.weeklyResetAfterSeconds))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            } else {
                Text("—")
                    .font(.title.bold())
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Sign in to AIQuota")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func countdownText(seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        if days > 0 { return "Resets \(days)d \(hours)h" }
        return "Resets \(hours)h \((seconds % 3600) / 60)m"
    }
}
