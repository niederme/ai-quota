import SwiftUI
import AIQuotaKit

struct WidgetMediumView: View {
    let entry: QuotaEntry

    var body: some View {
        Group {
            // Exactly one service enrolled → centered single gauge.
            // Zero (never enrolled / after reset) or two → dual layout.
            if entry.enrolledServices.count == 1 {
                singleLayout
            } else {
                dualLayout
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dualLayout: some View {
        HStack(spacing: 0) {
            gaugeSlot(for: .codex, size: 80).frame(maxWidth: .infinity)
            Divider().padding(.vertical, 12)
            gaugeSlot(for: .claude, size: 80).frame(maxWidth: .infinity)
        }
    }

    private var singleLayout: some View {
        // `enrolledServices.count == 1` is guaranteed at call site
        let service = entry.enrolledServices.first ?? .codex
        return gaugeSlot(for: service, size: 90)
    }

    // MARK: - Gauge slot

    @ViewBuilder
    private func gaugeSlot(for service: ServiceType, size: CGFloat) -> some View {
        switch service {
        case .codex:
            if let u = entry.codexUsage {
                WidgetGaugeView(
                    primaryPercent: u.hourlyUsedPercent,
                    primaryLimitReached: u.hourlyUsedPercent >= 100,
                    secondaryPercent: u.weeklyUsedPercent,
                    icon: "logo-openai",
                    label: "Codex",
                    primaryLabel: "5h",
                    secondaryLabel: "7-day",
                    resetSeconds: u.hourlyResetAfterSeconds,
                    weeklyResetSeconds: u.weeklyResetAfterSeconds,
                    secondaryLimitReached: u.isWeeklyExhausted,
                    size: size
                )
            } else {
                emptySlot(icon: "logo-openai", label: "Codex")
            }

        case .claude:
            if let u = entry.claudeUsage {
                WidgetGaugeView(
                    primaryPercent: u.usedPercent,
                    primaryLimitReached: u.limitReached,
                    secondaryPercent: Int(u.sevenDayUtilization.rounded()),
                    icon: "logo-claude",
                    label: "Claude Code",
                    primaryLabel: "5h",
                    secondaryLabel: "7-day",
                    resetSeconds: u.resetAfterSeconds,
                    weeklyResetSeconds: u.sevenDayResetAfterSeconds,
                    secondaryLimitReached: u.sevenDayUtilization >= 100,
                    size: size
                )
            } else {
                emptySlot(icon: "logo-claude", label: "Claude Code")
            }
        }
    }

    private func emptySlot(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundStyle(WidgetGaugeView.accent.opacity(0.3))
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            Text("Sign in to AIQuota").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}
