import SwiftUI
import AIQuotaKit

/// A Mac-sized version of the accepted iOS overview hierarchy: dial, one
/// account identity, plan, usage and reset context. The whole surface opens
/// details; account management lives in Settings and the context menu.
struct MacAccountCard: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var hovered = false

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
    private var awaitingConnection: Bool { loading && !connected && !hasReading }
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
            let unit = value.unit ?? "monthly allowance"
            let currency = unit.count == 3 && unit.lowercased() != "credit" ? unit.uppercased() : nil
            return (used, limit, unit, currency, value.resetAt)
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
            HStack(alignment: .top, spacing: 14) {
                MacAccountDial(icon: icon, primaryPercent: primaryPercent,
                               primaryLabel: primaryLabel, secondaryPercent: secondaryPercent,
                               loading: loading, connected: connected, hasIssue: issue != nil)
                    .frame(width: 100, height: 100)
                details
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(hovered || focused ? 0.07 : 0))
            }
        }
        .buttonStyle(.plain)
        .focused($focused)
        .onHover { hovered = $0 && !awaitingConnection }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: focused)
        .disabled(awaitingConnection)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(connected || hasReading ? "Open account details" : "Reconnect account")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(serviceName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
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
                Text(budgetSummary(budget))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.82))
                if let reset = budget.reset {
                    resetCaption(at: reset)
                }
            } else if let usage = codexUsage, usage.reportedWindowShape != nil {
                resetCaption(at: usage.reportedWindowShape == .dual ? usage.hourlyResetAt : usage.weeklyResetAt)
                if usage.reportedWindowShape == .dual { resetCaption("7d", at: usage.weeklyResetAt) }
            } else if let usage = claudeUsage {
                resetCaption(at: usage.resetAt)
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

    private func resetCaption(_ window: String? = nil, at date: Date?) -> some View {
        Text(resetText(window, at: date))
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color.gaugeAccent.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func resetText(_ window: String?, at date: Date?) -> String {
        let prefix = window.map { "\($0) " } ?? ""
        guard let date, date != .distantFuture, date != .distantPast else {
            return "\(prefix)Reset time unavailable"
        }
        guard date > .now else { return "\(prefix)Reset unconfirmed" }
        let day = date.formatted(.dateTime.weekday(.abbreviated))
        let time = date.formatted(.dateTime.hour().minute())
        return "\(prefix)Resets \(day) at \(time)"
    }

    private func amount(_ value: Double, currency: String?) -> String {
        if let currency { return value.formatted(.currency(code: currency)) }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func budgetSummary(_ budget: (used: Double, limit: Double, unit: String,
                                           currency: String?, reset: Date?)) -> String {
        let verb = account.provider == .claude || budget.currency != nil ? "Spent" : "Used"
        let suffix = budget.currency == nil && budget.unit.lowercased() == "credit" ? " credits" : ""
        return "\(verb) \(amount(budget.used, currency: budget.currency)) of \(amount(budget.limit, currency: budget.currency))\(suffix)"
    }

    private var accessibilitySummary: String {
        let identity = accountLabel.map { " · \($0)" } ?? ""
        let percentage = primaryPercent.map { ", \($0) percent used in \(primaryLabel)" } ?? ""
        let secondary = secondaryPercent.map { ", \($0) percent used in 7d" } ?? ""
        return "\(serviceName)\(identity)\(plan.map { ", \($0) plan" } ?? "")\(percentage)\(secondary)\(status.map { ", \($0)" } ?? "")"
    }
}
