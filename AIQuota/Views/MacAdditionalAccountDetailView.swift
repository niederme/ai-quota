import SwiftUI
import AIQuotaKit

/// Account-scoped detail for connections that do not use the legacy singleton.
struct MacAdditionalAccountDetailView: View {
    let session: AdditionalAccountSession
    let height: CGFloat
    let close: () -> Void
    let openSettings: () -> Void
    let reconnect: () -> Void

    private var serviceName: String { session.provider == .codex ? "Codex" : "Claude Code" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Label("Back", systemImage: "chevron.left")
                }
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Text(serviceName).font(.headline)
                Spacer()
                Button("Manage", action: openSettings)
            }
            .buttonStyle(.borderless)
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(session.account.displayLabel)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                    if let issue = session.issue {
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !session.isAuthenticated {
                        Button("Reconnect \(serviceName)", action: reconnect)
                            .disabled(session.isLoading)
                    }
                    if let usage = session.codexUsage {
                        codex(usage)
                    } else if let usage = session.claudeUsage {
                        claude(usage)
                    } else {
                        ContentUnavailableView(
                            session.isLoading ? "Loading usage" : "Usage unavailable",
                            systemImage: "chart.bar",
                            description: Text(session.isAuthenticated ? "Refresh this account to try again." : "Reconnect this account in Settings.")
                        )
                    }
                    Button("Refresh this account") { Task { await session.refresh() } }
                        .disabled(!session.isAuthenticated || session.isLoading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .frame(height: height, alignment: .top)
        .accessibilityIdentifier("additionalAccountDetail")
    }

    private func metric(_ name: String, _ value: String, reset: Date? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).fontWeight(.semibold).monospacedDigit()
                if let reset {
                    Text(ResetTimeTextFormatter.compactWindowCaption(name, resetAt: reset))
                        .font(.caption)
                        .foregroundStyle(Color.gaugeAccent)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func codex(_ usage: CodexUsage) -> some View {
        VStack(spacing: 12) {
            metric("Plan", usage.displayPlan)
            if let budget = usage.displayableMonthlyBudget, let used = budget.used, let limit = budget.limit {
                metric("Monthly \(budget.unit ?? "allowance")",
                       "\(used.formatted()) of \(limit.formatted())", reset: budget.resetAt)
            }
            if usage.reportedWindowShape == .dual {
                metric("5h", "\(usage.hourlyUsedPercent)% used", reset: usage.hourlyResetAt)
            }
            if usage.reportedWindowShape != nil {
                metric("7d", "\(usage.weeklyUsedPercent)% used", reset: usage.weeklyResetAt)
            }
            if let balance = usage.creditBalance {
                metric("Credit balance", balance.formatted(.number.precision(.fractionLength(0...2))))
            }
            metric("Updated", usage.fetchedAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private func claude(_ usage: ClaudeUsage) -> some View {
        VStack(spacing: 12) {
            metric("Plan", usage.planLabel.displayName)
            if let spend = usage.spendLimit {
                metric("Monthly spend",
                       "\(spend.used.formatted()) of \(spend.limit.formatted()) \(spend.currencyCode ?? "")")
            }
            if let fiveHour = usage.fiveHourUtilization {
                metric("5h", "\(Int(fiveHour.rounded()))% used", reset: usage.fiveHourResetsAt)
            }
            if let sevenDay = usage.sevenDayUtilization {
                metric("7d", "\(Int(sevenDay.rounded()))% used", reset: usage.sevenDayResetsAt)
            }
            metric("Updated", usage.fetchedAt.formatted(date: .abbreviated, time: .shortened))
        }
    }
}
