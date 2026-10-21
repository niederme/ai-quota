import SwiftUI
import AIQuotaKit

/// A Mac-sized version of the accepted iOS overview hierarchy: dial, one
/// account identity, plan, usage and reset context. The whole surface opens
/// details; account management lives in Settings and the context menu.
struct MacAccountCard: View {
    @Environment(QuotaViewModel.self) private var viewModel

    let account: ConnectedAccount
    let session: AdditionalAccountSession?
    let showsAccountLabel: Bool
    let open: () -> Void
    let reconnect: () -> Void

    private var codexUsage: CodexUsage? {
        MacAccountOverviewUsage.codex(account: account, isolated: session?.codexUsage,
                                      primary: viewModel.codexUsage)
    }
    private var claudeUsage: ClaudeUsage? {
        MacAccountOverviewUsage.claude(account: account, isolated: session?.claudeUsage,
                                       primary: viewModel.claudeUsage)
    }
    private var hasReading: Bool { codexUsage != nil || claudeUsage != nil }
    private var loading: Bool {
        session?.isLoading ?? (account.provider == .codex ? viewModel.isCodexLoading : viewModel.isClaudeLoading)
    }
    private var connected: Bool {
        session?.isAuthenticated ?? (account.provider == .codex ? viewModel.isCodexAuthenticated : viewModel.isClaudeAuthenticated)
    }
    private var issue: String? {
        session?.issue ?? (account.provider == .codex ? viewModel.codexError?.localizedDescription : viewModel.claudeError?.localizedDescription)
    }
    private var serviceName: String { account.provider == .codex ? "Codex" : "Claude Code" }
    private var icon: String { account.provider == .codex ? "logo-openai" : "logo-claude" }
    private var plan: String? {
        account.provider == .codex ? codexUsage?.displayPlan : claudeUsage?.planLabel.displayName
    }
    private var accountLabel: String? {
        let label = account.displayLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return nil }
        if !showsAccountLabel && label.caseInsensitiveCompare("Personal") == .orderedSame { return nil }
        let parts = label.split(whereSeparator: \.isWhitespace)
        if parts.count == 2,
           ["account", "service"].contains(parts[0].lowercased()),
           parts[1].allSatisfy(\.isNumber) { return nil }
        return label
    }
    private var budget: (used: Double, limit: Double, unit: String, currency: String?, reset: Date?)? {
        if account.provider == .codex, codexUsage?.reportedWindowShape == nil,
           let value = codexUsage?.displayableMonthlyBudget,
           let used = value.used, let limit = value.limit {
            return (used, limit, value.unit ?? "monthly allowance", nil, value.resetAt)
        }
        if account.provider == .claude, claudeUsage?.primaryMetric.kind == .spendLimit,
           let value = claudeUsage?.spendLimit,
           value.used.isFinite, value.limit.isFinite, value.limit > 0 {
            return (value.used, value.limit, "monthly spend", value.currencyCode, nil)
        }
        return nil
    }
    private var primaryPercent: Int? {
        if let budget { return Int((budget.used / budget.limit * 100).rounded()) }
        if let usage = codexUsage {
            switch usage.reportedWindowShape {
            case .dual: return usage.hourlyUsedPercent
            case .weeklyOnly: return usage.weeklyUsedPercent
            case nil: return nil
            }
        }
        return claudeUsage?.usedPercent
    }
    private var secondaryPercent: Int? {
        if codexUsage?.reportedWindowShape == .dual { return codexUsage?.weeklyUsedPercent }
        if let usage = claudeUsage, usage.primaryMetric.kind != .sevenDay,
           let weekly = usage.sevenDayUtilization { return Int(weekly.rounded()) }
        return nil
    }
    private var primaryLabel: String {
        if budget != nil { return "Monthly" }
        if account.provider == .codex { return codexUsage?.reportedWindowShape == .dual ? "5h" : "7d" }
        return claudeUsage?.primaryMetricLabel ?? "5h"
    }

    var body: some View {
        Button(action: connected || hasReading ? open : reconnect) {
            HStack(alignment: .top, spacing: 16) {
                MacAccountDial(icon: icon, primaryPercent: primaryPercent,
                               primaryLabel: primaryLabel, secondaryPercent: secondaryPercent,
                               loading: loading, connected: connected, hasIssue: issue != nil)
                    .frame(width: 112, height: 112)
                details
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.24),
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(loading && !connected && !hasReading)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(connected || hasReading ? "Open account details" : "Reconnect account")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(serviceName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            if let plan {
                Text("\(plan) plan" + (accountLabel.map { " · \($0)" } ?? ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let accountLabel {
                Text(accountLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            if let budget {
                Text("\(amount(budget.used, currency: budget.currency)) of \(amount(budget.limit, currency: budget.currency))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(budget.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let reset = budget.reset {
                    resetCaption("Monthly", at: reset)
                }
            } else if let usage = codexUsage, usage.reportedWindowShape != nil {
                resetCaption(primaryLabel, at: usage.reportedWindowShape == .dual ? usage.hourlyResetAt : usage.weeklyResetAt)
                if usage.reportedWindowShape == .dual { resetCaption("7d", at: usage.weeklyResetAt) }
            } else if let usage = claudeUsage {
                resetCaption(usage.primaryMetricLabel, at: usage.resetAt)
                if secondaryPercent != nil { resetCaption("7d", at: usage.sevenDayResetsAt) }
            }
            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(issue == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .fixedSize(horizontal: false, vertical: true)
                    .help(issue ?? status)
            }
        }
        .padding(.top, 2)
    }

    private var status: String? {
        if issue != nil { return hasReading ? "Couldn’t update · Saved reading" : "Couldn’t load allowance" }
        if !connected { return loading ? "Connecting…" : (hasReading ? "Reconnect to update" : "Not connected") }
        if !hasReading { return loading ? "Loading allowance…" : "No reading yet" }
        if loading { return "Refreshing…" }
        return nil
    }

    private func resetCaption(_ window: String, at date: Date?) -> some View {
        Text(ResetTimeTextFormatter.compactWindowCaption(window, resetAt: date))
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color.gaugeAccent.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func amount(_ value: Double, currency: String?) -> String {
        if let currency { return value.formatted(.currency(code: currency)) }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private var accessibilitySummary: String {
        let identity = accountLabel.map { " · \($0)" } ?? ""
        let percentage = primaryPercent.map { ", \($0) percent \(primaryLabel)" } ?? ""
        return "\(serviceName)\(identity)\(plan.map { ", \($0) plan" } ?? "")\(percentage)\(status.map { ", \($0)" } ?? "")"
    }
}

private struct MacAccountDial: View {
    let icon: String
    let primaryPercent: Int?
    let primaryLabel: String
    let secondaryPercent: Int?
    let loading: Bool
    let connected: Bool
    let hasIssue: Bool

    private var tint: Color {
        guard connected, !hasIssue else { return .secondary }
        let worst = max(primaryPercent ?? 0, secondaryPercent ?? 0)
        if worst >= 95 { return .critical }
        if worst >= 85 { return .warningAmber }
        return .gaugeAccent
    }

    var body: some View {
        ZStack {
            arc(percent: primaryPercent, lineWidth: secondaryPercent == nil ? 11 : 8, opacity: 1)
            if secondaryPercent != nil {
                arc(percent: secondaryPercent, lineWidth: 7, opacity: 0.65)
                    .padding(10)
            }
            VStack(spacing: 4) {
                Image(icon).resizable().scaledToFit().frame(width: 18, height: 18)
                if loading && primaryPercent == nil {
                    ProgressView().controlSize(.mini)
                } else if let primaryPercent {
                    if primaryLabel == "Monthly" {
                        Text("\(primaryPercent)%")
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                        Text("Monthly")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(primaryPercent)% \(primaryLabel)")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    }
                    if let secondaryPercent {
                        Text("\(secondaryPercent)% 7d")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .opacity(0.75)
                    }
                } else {
                    Text("—").font(.subheadline)
                }
            }
            .foregroundStyle(tint)
        }
        .frame(width: 112, height: 112)
        .accessibilityHidden(true)
    }

    private func arc(percent: Int?, lineWidth: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(.fill.tertiary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt,
                                                           dash: percent == nil && !loading ? [3, 4] : []))
            if connected && !loading, let percent {
                Circle().trim(from: 0, to: 0.75 * Double(max(0, min(100, percent))) / 100)
                    .stroke(tint.opacity(opacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
        }
        .rotationEffect(.degrees(135))
    }
}
