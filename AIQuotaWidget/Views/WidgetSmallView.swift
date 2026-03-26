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
                        icon: "logo-claude",
                        label: "Claude Code",
                        primaryLabel: "5h",
                        secondaryLabel: "7-day",
                        resetSeconds: u.resetAfterSeconds,
                        weeklyResetSeconds: u.sevenDayResetAfterSeconds,
                        secondaryLimitReached: u.sevenDayUtilization >= 100,
                        size: 90
                    )
                } else {
                    emptyView("Claude Code")
                }
            } else {
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
                        size: 90
                    )
                } else {
                    emptyView("Codex")
                }
            }
        }
        .padding(8)
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
