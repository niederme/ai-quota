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
                        icon: "logo-openai",
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
        .overlay(alignment: .bottomTrailing) {
            Button(intent: RefreshWidgetIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
    }

    private func emptyView(_ name: String) -> some View {
        VStack(spacing: 6) {
            Text("—").font(.title.bold()).foregroundStyle(.tertiary)
            Text(name).font(.caption2.bold()).foregroundStyle(.secondary)
            Text("Sign in to AIQuota").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}
