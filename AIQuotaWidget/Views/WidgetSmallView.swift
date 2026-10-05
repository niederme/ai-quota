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
                        showsPrimaryMetric: true,
                        secondaryPercent: Int(u.sevenDayUtilization?.rounded() ?? 0),
                        showsSecondaryMetric: true,
                        icon: "logo-claude",
                        label: "Claude Code",
                        primaryLabel: u.primaryMetricLabel,
                        secondaryLabel: "7-day",
                        resetSeconds: u.resetAfterSeconds ?? 0,
                        weeklyResetSeconds: u.sevenDayResetAfterSeconds ?? 0,
                        secondaryLimitReached: (u.sevenDayUtilization ?? 0) >= 100,
                        size: 90
                    )
                } else {
                    emptyView("Claude Code")
                }
            } else {
                if let u = entry.codexUsage {
                    let hasHourlyWindow = u.hasHourlyWindow
                    let weeklyOnly = u.reportsWeeklyOnlyWindow
                    WidgetGaugeView(
                        primaryPercent: weeklyOnly ? u.weeklyUsedPercent : (hasHourlyWindow ? u.hourlyUsedPercent : 0),
                        primaryLimitReached: weeklyOnly ? u.isWeeklyExhausted : (hasHourlyWindow && u.hourlyUsedPercent >= 100),
                        showsPrimaryMetric: weeklyOnly || hasHourlyWindow,
                        secondaryPercent: u.weeklyUsedPercent,
                        showsSecondaryMetric: !weeklyOnly,
                        icon: "logo-openai",
                        label: "Codex",
                        primaryLabel: weeklyOnly ? "7d" : "5h",
                        secondaryLabel: "7-day",
                        resetSeconds: weeklyOnly ? u.weeklyResetAfterSeconds : u.hourlyResetAfterSeconds,
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
