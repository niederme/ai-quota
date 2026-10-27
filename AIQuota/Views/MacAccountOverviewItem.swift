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
    let tokenHistory: CodexTokenHistory?
    let availableWidth: CGFloat
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
        if account.connectionKind == .isolated {
            guard let session else { return false }
            return session.isLoading || session.state == .unknown ||
                session.state == .restoringSession || session.state == .signingIn
        }
        return account.provider == .codex
            ? viewModel.isCodexLoading || viewModel.isCodexRecovering
            : viewModel.isClaudeLoading || viewModel.isClaudeRecovering
    }
    private var connected: Bool {
        if account.connectionKind == .isolated { return session?.isAuthenticated == true }
        return account.provider == .codex ? viewModel.isCodexAuthenticated : viewModel.isClaudeAuthenticated
    }
    private var issue: String? {
        if account.connectionKind == .isolated { return session?.issue }
        return account.provider == .codex ? viewModel.codexError?.localizedDescription : viewModel.claudeError?.localizedDescription
    }
    private var serviceName: String { account.provider == .codex ? "Codex" : "Claude" }
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
        if budget != nil { return CalendarMonthLabel.compact(containing: readingAt) }
        if account.provider == .codex { return codexUsage?.reportedWindowShape == .dual ? "5h" : "7d" }
        return claudeUsage?.primaryMetricLabel ?? "5h"
    }

    private var readingAt: Date {
        codexUsage?.fetchedAt ?? claudeUsage?.fetchedAt ?? .now
    }

    var body: some View {
        Button(action: connected || hasReading ? open : reconnect) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 20) {
                    MacAccountDial(icon: icon, primaryPercent: primaryPercent,
                                   primaryLabel: primaryLabel, secondaryPercent: secondaryPercent,
                                   loading: loading, connected: connected || (loading && hasReading),
                                   hasIssue: !loading && issue != nil)
                        .help(budget == nil ? primaryLabel : "\(CalendarMonthLabel.spoken(containing: readingAt)). Reset uses the provider's date.")
                    details
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                if connected || loading, account.provider == .codex, let tokenHistory,
                   tokenHistory.isAttributed(toWorkspaceID: account.workspaceID),
                   CodexTokenHistoryView.hasVisibleData(tokenHistory) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Token activity")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("Workspace token activity is separate from monthly credit usage.")
                        CodexTokenHistoryView(history: tokenHistory, availableWidth: availableWidth)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .opacity(loading ? 0.45 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 24))
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.overviewPrimary.opacity(hovered || focused ? 0.07 : 0))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(Color.overviewPrimary.opacity(0.16), lineWidth: 1)
                    }
            }
            .overlay {
                if loading {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(Color.overviewPrimary)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
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
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(serviceName)
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.25)
                    .foregroundStyle(Color.overviewPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let plan {
                    Text("\(plan) plan" + (accountLabel.map { " · \($0)" } ?? ""))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.overviewPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let accountLabel {
                    Text(accountLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.overviewPrimary)
                }
            }
            if let budget {
                Text(budgetSummary(budget))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Color.overviewSecondary)
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
                    .font(.system(size: 13))
                    .foregroundStyle(issue == nil ? AnyShapeStyle(Color.overviewSecondary) : AnyShapeStyle(Color.overviewWarning))
                    .fixedSize(horizontal: false, vertical: true)
                    .help(issue ?? status)
            }
        }
        .padding(.top, 2)
    }

    private var status: String? {
        // Progress is overlaid so a refresh never inserts an extra layout row.
        // Recovery also counts as loading: the saved reading remains visible
        // until authentication has a verdict.
        if loading { return nil }
        if issue != nil { return hasReading ? "Couldn’t update · Saved reading" : "Couldn’t load allowance" }
        if !connected { return hasReading ? "Reconnect to update" : "Not connected" }
        if !hasReading { return "No reading yet" }
        return nil
    }

    private func resetCaption(_ window: String? = nil, at date: Date?) -> some View {
        Text(resetText(window, at: date))
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(Color.overviewResetAccent)
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
        let period = budget == nil ? primaryLabel : CalendarMonthLabel.spoken(containing: readingAt)
        let percentage = primaryPercent.map { ", \($0) percent used, \(period)" } ?? ""
        let secondary = secondaryPercent.map { ", \($0) percent used in 7d" } ?? ""
        let activity = loading ? (hasReading ? "Refreshing saved reading" : "Connecting") : status
        return "\(serviceName)\(identity)\(plan.map { ", \($0) plan" } ?? "")\(percentage)\(secondary)\(activity.map { ", \($0)" } ?? "")"
    }
}
