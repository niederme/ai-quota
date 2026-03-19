import SwiftUI
import AIQuotaKit

struct WidgetSmallView: View {
    let entry: QuotaEntry

    private var showClaude: Bool { entry.configuration.service == .claude }

    var body: some View {
        Group {
            if showClaude {
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
                        size: 86
                    )
                } else {
                    emptyView("Claude Code")
                }
            } else {
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
                        size: 86
                    )
                } else {
                    emptyView("Codex")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyView(_ name: String) -> some View {
        VStack(spacing: 6) {
            Text("—").font(.title.bold()).foregroundStyle(.tertiary)
            Text(name).font(.caption2.bold()).foregroundStyle(.secondary)
            Text("Sign in to AIQuota").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}
