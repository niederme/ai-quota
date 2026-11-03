import SwiftUI
import AIQuotaKit

struct WidgetSmallView: View {
    let entry: QuotaEntry

    private var showClaude: Bool { entry.selectedService == .claude }

    var body: some View {
        Group {
            if entry.selectedAccountUnavailable {
                WidgetMissingSelectionView(label: entry.displayName(for: entry.selectedService))
            } else if showClaude {
                if let u = entry.claudeUsage {
                    WidgetGaugeView(
                        primaryPercent: u.usedPercent,
                        primaryLimitReached: u.limitReached,
                        showsPrimaryMetric: true,
                        secondaryPercent: Int(u.sevenDayUtilization?.rounded() ?? 0),
                        showsSecondaryMetric: true,
                        icon: "logo-claude",
                        label: entry.displayName(for: .claude),
                        primaryLabel: u.primaryMetricLabel,
                        secondaryLabel: "7-day",
                        resetSeconds: u.resetAfterSeconds ?? 0,
                        weeklyResetSeconds: u.sevenDayResetAfterSeconds ?? 0,
                        secondaryLimitReached: (u.sevenDayUtilization ?? 0) >= 100,
                        size: 90
                    )
                } else {
                    emptyView(entry.displayName(for: .claude))
                }
            } else {
                if let u = entry.codexUsage {
                    if u.reportedWindowShape == nil, let budget = u.displayableMonthlyBudget {
                        WidgetBudgetView(budget: budget, size: 90, label: entry.displayName(for: .codex))
                    } else if u.reportedWindowShape != nil {
                    let hasHourlyWindow = u.hasHourlyWindow
                    let weeklyOnly = u.reportsWeeklyOnlyWindow
                    WidgetGaugeView(
                        primaryPercent: weeklyOnly ? u.weeklyUsedPercent : (hasHourlyWindow ? u.hourlyUsedPercent : 0),
                        primaryLimitReached: weeklyOnly ? u.isWeeklyExhausted : (hasHourlyWindow && u.hourlyUsedPercent >= 100),
                        showsPrimaryMetric: weeklyOnly || hasHourlyWindow,
                        secondaryPercent: u.weeklyUsedPercent,
                        showsSecondaryMetric: !weeklyOnly,
                        icon: "logo-openai",
                        label: entry.displayName(for: .codex),
                        primaryLabel: weeklyOnly ? "7d" : "5h",
                        secondaryLabel: "7-day",
                        resetSeconds: weeklyOnly ? u.weeklyResetAfterSeconds : u.hourlyResetAfterSeconds,
                        weeklyResetSeconds: u.weeklyResetAfterSeconds,
                        secondaryLimitReached: u.isWeeklyExhausted,
                        size: 90
                    )
                    } else {
                        unavailableView(entry.displayName(for: .codex))
                    }
                } else {
                    emptyView(entry.displayName(for: .codex))
                }
            }
        }
        .privacySensitive()
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

    private func unavailableView(_ name: String) -> some View {
        VStack(spacing: 6) {
            Text("—").font(.title.bold()).foregroundStyle(.tertiary)
            Text(name).font(.caption2.bold())
            Text("Usage unavailable").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}

struct WidgetMissingSelectionView: View {
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2).foregroundStyle(.secondary)
            Text(label).font(.caption.bold())
            Text("Edit widget to choose a connection.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .privacySensitive()
    }
}
