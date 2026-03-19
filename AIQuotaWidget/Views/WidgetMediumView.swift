import SwiftUI
import AIQuotaKit

struct WidgetMediumView: View {
    let entry: QuotaEntry

    var body: some View {
        HStack(spacing: 0) {
            // Left: Codex
            gaugeSlot(for: .codex)
                .frame(maxWidth: .infinity)

            Divider().padding(.vertical, 12)

            // Right: Claude Code
            gaugeSlot(for: .claude)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Gauge slot

    @ViewBuilder
    private func gaugeSlot(for service: ServiceType) -> some View {
        switch service {
        case .codex:
            if let u = entry.codexUsage {
                WidgetGaugeView(
                    primaryPercent: u.hourlyUsedPercent,
                    primaryLimitReached: u.limitReached,
                    secondaryPercent: u.weeklyUsedPercent,
                    icon: "brain.fill",
                    label: "Codex",
                    primaryLabel: "5h",
                    secondaryLabel: "7-day",
                    resetSeconds: u.hourlyResetAfterSeconds,
                    size: 80
                )
            } else {
                emptySlot(icon: "brain.fill", label: "Codex")
            }

        case .claude:
            if let u = entry.claudeUsage {
                WidgetGaugeView(
                    primaryPercent: u.usedPercent,
                    primaryLimitReached: u.limitReached,
                    secondaryPercent: Int(u.sevenDayUtilization.rounded()),
                    icon: "sparkles",
                    label: "Claude Code",
                    primaryLabel: "5h",
                    secondaryLabel: "7-day",
                    resetSeconds: u.resetAfterSeconds,
                    size: 80
                )
            } else {
                emptySlot(icon: "sparkles", label: "Claude Code")
            }
        }
    }

    private func emptySlot(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(WidgetGaugeView.accent.opacity(0.3))
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            Text("Sign in to AIQuota").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}
