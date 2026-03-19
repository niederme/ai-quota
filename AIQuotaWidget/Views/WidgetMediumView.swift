import SwiftUI
import AIQuotaKit

struct WidgetMediumView: View {
    let entry: QuotaEntry

    private var showClaude: Bool {
        entry.configuration.service == .claude
    }

    var body: some View {
        if showClaude {
            if let claude = entry.claudeUsage {
                claudeView(claude)
            } else {
                emptyView
            }
        } else {
            if let codex = entry.codexUsage {
                codexView(codex)
            } else {
                emptyView
            }
        }
    }

    // MARK: - Codex layout

    private func codexView(_ usage: CodexUsage) -> some View {
        let pct          = usage.hourlyUsedPercent
        let limitReached = usage.limitReached
        let tintColor: Color = limitReached ? .red
            : pct < 60 ? .green : pct < 85 ? .yellow : .red

        return HStack(spacing: 0) {
            // Left: gauge + %
            VStack(spacing: 0) {
                Spacer()
                Label("Codex", systemImage: "brain.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(limitReached ? .red : .purple)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
                VStack(spacing: 3) {
                    Image(nsImage: GaugeImageMaker.image(
                        usedPercent: pct, limitReached: limitReached,
                        isLoading: false, size: 48
                    ))
                    .frame(width: 48, height: 48)
                    Text("\(pct)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .foregroundStyle(tintColor)
                    Text("5h window")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity)

            Divider().padding(.vertical, 10)

            // Right: stats
            VStack(alignment: .leading, spacing: 5) {
                Spacer()
                if limitReached {
                    Label("Rate limit reached", systemImage: "exclamationmark.octagon")
                        .font(.caption2.bold()).foregroundStyle(.red)
                    Divider()
                }
                statRow("Remaining", "\(100 - usage.hourlyUsedPercent)%", "sparkles", tintColor)
                statRow("7-day", "\(usage.weeklyUsedPercent)%", "calendar", .secondary)
                statRow("Plan", usage.planType.capitalized, "person.fill", .secondary)
                if let balance = usage.creditBalance {
                    statRow("Credits", "\(Int(balance))", "creditcard.fill", .secondary)
                }
                Spacer()
                Text(countdownText(seconds: usage.hourlyResetAfterSeconds))
                    .font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Claude layout

    private func claudeView(_ usage: ClaudeUsage) -> some View {
        let pct          = usage.usedPercent
        let limitReached = usage.limitReached
        let claudeColor  = Color(red: 0.8, green: 0.45, blue: 0.1)
        let tintColor: Color = limitReached ? .red
            : pct < 60 ? .green : pct < 85 ? .yellow : .red

        return HStack(spacing: 0) {
            // Left: gauge + %
            VStack(spacing: 0) {
                Spacer()
                Label("Claude Code", systemImage: "sparkles")
                    .font(.caption2.bold())
                    .foregroundStyle(limitReached ? .red : claudeColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
                VStack(spacing: 3) {
                    Image(nsImage: GaugeImageMaker.image(
                        usedPercent: pct, limitReached: limitReached,
                        isLoading: false, size: 48
                    ))
                    .frame(width: 48, height: 48)
                    Text("\(pct)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .foregroundStyle(tintColor)
                    Text("5h window")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity)

            Divider().padding(.vertical, 10)

            // Right: stats
            VStack(alignment: .leading, spacing: 5) {
                Spacer()
                if limitReached {
                    Label("Limit reached", systemImage: "exclamationmark.octagon")
                        .font(.caption2.bold()).foregroundStyle(.red)
                    Divider()
                }
                statRow("7-day", "\(Int(usage.sevenDayUtilization.rounded()))%", "calendar", .secondary)
                statRow("Plan", usage.planDisplayName, "person.fill", .secondary)
                if let extra = usage.extraUsage, extra.isEnabled {
                    statRow("Extra", "\(Int(extra.usedCredits))/\(extra.monthlyLimit)", "plus.circle.fill", .secondary)
                }
                Spacer()
                Text(countdownText(seconds: usage.resetAfterSeconds))
                    .font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 8) {
            Text("—").font(.title.bold()).foregroundStyle(.tertiary)
            Text("Sign in to AIQuota").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shared helpers

    private func statRow(_ label: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(color).frame(width: 14)
            Text(label + ":").font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption2.monospacedDigit().bold()).foregroundStyle(.primary)
        }
    }

    private func countdownText(seconds: Int) -> String {
        let days  = seconds / 86400
        let hours = (seconds % 86400) / 3600
        if days > 0 { return "Resets in \(days)d \(hours)h" }
        return "Resets in \(hours)h \((seconds % 3600) / 60)m"
    }
}
