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
        VStack(alignment: .leading, spacing: 6) {
            Label("Codex", systemImage: limitReached ? "exclamationmark.octagon.fill" : "brain.fill")
                .font(.caption2.bold())
                .foregroundStyle(limitReached ? .red : .purple)

            Spacer()

            if let usage = entry.usage {
                HStack(alignment: .center, spacing: 6) {
                    Image(nsImage: GaugeImageMaker.image(
                        usedPercent: pct,
                        limitReached: limitReached,
                        isLoading: false,
                        size: 36
                    ))
                    .frame(width: 36, height: 36)

                    Text("\(pct)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .foregroundStyle(tintColor)
                }

                Gauge(value: fraction) { EmptyView() }
                    .gaugeStyle(.linearCapacity)
                    .tint(tintColor)

                if limitReached {
                    Text("Limit reached")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                } else {
                    Text("\(usage.weeklyRemaining)% left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(.title.bold())
                    .foregroundStyle(.tertiary)
                Text("Sign in")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let usage = entry.usage {
                Text(countdownText(seconds: usage.weeklyResetAfterSeconds))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func countdownText(seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        if days > 0 { return "Resets \(days)d \(hours)h" }
        return "Resets \(hours)h \((seconds % 3600) / 60)m"
    }
}
