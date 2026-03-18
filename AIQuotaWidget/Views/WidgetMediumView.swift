import SwiftUI
import AIQuotaKit

struct WidgetMediumView: View {
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
        HStack(spacing: 0) {
            // Left: gauge icon + percentage
            VStack(spacing: 0) {
                Spacer()

                Label("Codex", systemImage: limitReached ? "exclamationmark.octagon.fill" : "brain.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(limitReached ? .red : .purple)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                if entry.usage != nil {
                    VStack(spacing: 3) {
                        Image(nsImage: GaugeImageMaker.image(
                            usedPercent: pct,
                            limitReached: limitReached,
                            isLoading: false,
                            size: 48
                        ))
                        .frame(width: 48, height: 48)

                        Text("\(pct)%")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                            .foregroundStyle(tintColor)

                        Text("weekly usage")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("—").font(.title.bold()).foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity)

            Divider()
                .padding(.vertical, 10)

            // Right: detail rows
            VStack(alignment: .leading, spacing: 5) {
                Spacer()
                if let usage = entry.usage {
                    if limitReached {
                        Label("Limit reached", systemImage: "exclamationmark.octagon")
                            .font(.caption2.bold())
                            .foregroundStyle(.red)
                        Divider()
                    }
                    statRow("Remaining", "\(usage.weeklyRemaining)%", "sparkles", tintColor)
                    statRow("Plan", usage.planType.capitalized, "person.fill", .secondary)
                    if let balance = usage.creditBalance {
                        statRow("Credits", "\(Int(balance))", "creditcard.fill", .secondary)
                    }
                    Spacer()
                    Text(countdownText(seconds: usage.weeklyResetAfterSeconds))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Text("Sign in to\nAIQuota")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statRow(_ label: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(color).frame(width: 14)
            Text(label + ":").font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption2.monospacedDigit().bold()).foregroundStyle(.primary)
        }
    }

    private func countdownText(seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        if days > 0 { return "Resets in \(days)d \(hours)h" }
        return "Resets in \(hours)h \((seconds % 3600) / 60)m"
    }
}
