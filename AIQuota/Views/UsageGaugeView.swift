import SwiftUI
import AIQuotaKit

// UsageGaugeView is now embedded directly in PopoverView.
// This file kept as a standalone reusable component for potential other use.

struct UsageGaugeView: View {
    let usage: CodexUsage?

    private var pct: Double { usage?.weeklyPercentFraction ?? 0 }

    private var gaugeTint: Color {
        switch usage?.weeklyUsedPercent ?? 0 {
        case ..<60: return .green
        case ..<85: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Gauge(value: pct) {
                EmptyView()
            } currentValueLabel: {
                Text(usage.map { "\($0.weeklyUsedPercent)%" } ?? "—")
                    .font(.caption.monospacedDigit())
            }
            .gaugeStyle(.linearCapacity)
            .tint(gaugeTint)
            .animation(.easeInOut(duration: 0.4), value: pct)

            HStack {
                Text("\(usage?.weeklyUsedPercent ?? 0)% used")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(usage?.weeklyRemaining ?? 0)% left")
                    .foregroundStyle(gaugeTint)
            }
            .font(.caption2)
        }
        .padding(12)
    }
}
