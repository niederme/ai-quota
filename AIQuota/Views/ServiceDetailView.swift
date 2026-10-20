import SwiftUI
import AIQuotaKit
import MobileAccessCore

/// Uses the same analytics cards and category destinations as the iOS sheet.
struct ServiceDetailView: View {
    let service: ServiceType
    let height: CGFloat
    let close: () -> Void
    let openAccount: () -> Void
    @Environment(QuotaViewModel.self) private var viewModel

    private var isCodex: Bool { service == .codex }
    private var name: String { isCodex ? "Codex" : "Claude" }
    private var busy: Bool {
        isCodex ? viewModel.isCodexLoading || viewModel.isUsageHistoryLoading : viewModel.isClaudeLoading
    }
    private var connected: Bool { isCodex ? viewModel.isCodexAuthenticated : viewModel.isClaudeAuthenticated }
    private var error: NetworkError? { isCodex ? viewModel.codexError : viewModel.claudeError }
    private var reading: QuotaReading? {
        #if DEMO_MODE
        return MacAnalyticsDemo.reading(service)
        #else
        if isCodex, let usage = viewModel.codexUsage {
            let monthlyBudget = (usage.reportedWindowShape == nil ? usage.displayableMonthlyBudget : nil).flatMap {
                MobileAccessCore.MonthlyBudget(used: $0.used, limit: $0.limit,
                    unit: $0.unit, resetsAt: $0.resetAt)
            }
            return QuotaReading(fetchedAt: usage.fetchedAt, shortTerm: nil, weekly: nil,
                metadata: AccountMetadata(plan: usage.planType, balanceUSD: usage.creditBalance,
                    usageSpent: usage.bonusCreditsSpentThisMonth.map { $0 / 25 }, usageCurrency: "USD"),
                monthlyBudget: monthlyBudget)
        }
        if !isCodex, let usage = viewModel.claudeUsage {
            let monthlyBudget = usage.spendLimit.flatMap {
                MobileAccessCore.MonthlyBudget(used: $0.used, limit: $0.limit,
                    unit: $0.currencyCode)
            }
            return QuotaReading(fetchedAt: usage.fetchedAt, shortTerm: nil, weekly: nil,
                metadata: AccountMetadata(plan: usage.planDisplayName, balanceUSD: nil,
                    usageSpent: usage.usageCredits?.spent, usageCurrency: usage.usageCredits?.currencyCode),
                claudeBreakdown: usage.weeklyBreakdown, monthlyBudget: monthlyBudget)
        }
        return nil
        #endif
    }
    private var history: CodexUsageHistory? {
        #if DEMO_MODE
        MacAnalyticsDemo.history
        #else
        viewModel.codexUsageHistory
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: close) {
                    Image(systemName: "chevron.left").frame(width: 16, height: 16)
                }
                .buttonStyle(AnalyticsHoverButtonStyle()).accessibilityLabel("Back to overview").help("Back to overview")
                Image(isCodex ? "logo-openai" : "logo-claude")
                    .resizable().scaledToFit().frame(width: 22, height: 22)
                    .foregroundStyle(Color.gaugeAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    Text(reading?.metadata?.displayPlan.map { "\($0) plan" } ?? "Plan not reported")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(action: refresh) { Image(systemName: "arrow.clockwise").frame(width: 16, height: 16) }
                    .buttonStyle(AnalyticsHoverButtonStyle()).disabled(busy || !connected)
                    .accessibilityLabel("Refresh \(name) details").help(refreshHelp)
            }.padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !connected {
                            Label("Reconnect to update details. Your last reading is retained.", systemImage: "person.crop.circle.badge.exclamationmark")
                                .foregroundStyle(Color.warningAmber)
                        }
                        if let budget = reading?.monthlyBudget {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Monthly allowance").font(.headline)
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(Int(budget.usedPercent.rounded()))%")
                                        .font(.largeTitle.bold()).monospacedDigit()
                                    Text("used").foregroundStyle(.secondary)
                                }
                                Text("\(budget.amountText(budget.used)) of \(budget.amountText(budget.limit))")
                                    .font(.title3.weight(.semibold)).monospacedDigit()
                                Text(budget.unitLabel).foregroundStyle(.secondary)
                                ProgressView(value: budget.usedPercent, total: 100)
                                    .tint(Color.gaugeAccent)
                                if let reset = budget.confirmedResetDescription() {
                                    Text(reset).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            .modifier(AnalyticsCard())
                        }
                        if isCodex, let history, history.days.contains(where: { $0.credits != nil }) {
                            CodexAnalyticsView(reading: reading, history: history,
                                historyUnavailable: viewModel.usageHistoryFailed,
                                busy: busy, refresh: refresh)
                        } else if !isCodex, reading?.claudeBreakdown != nil {
                            ClaudeAnalyticsView(reading: reading, busy: busy, failed: error != nil || !connected, refresh: refresh)
                        }
                        if let error {
                            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                                .font(.callout).foregroundStyle(Color.warningAmber)
                        }
                        if !connected || isCodex { Divider() }
                        if !connected {
                            Button(action: openAccount) {
                                Label("Reconnect \(name)", systemImage: "person.crop.circle")
                            }
                        }
                        if isCodex {
                            Button { NSWorkspace.shared.open(CodexResetNotice.website) } label: {
                                Label("Check Codex resets", systemImage: "arrow.up.right")
                            }
                        } else {
                            Button { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!) } label: {
                                Label("View spend and skills in Claude", systemImage: "arrow.up.right")
                            }
                        }
                    }.padding(16)
                }
            }
        }
        .tint(Color.gaugeAccent)
        .frame(height: height)
        .accessibilityIdentifier("serviceDetailView")
        .task(id: connected) {
            if isCodex, connected { viewModel.refreshUsageHistory() }
        }
    }

    private var refreshHelp: String {
        let freshness = reading.map { analyticsFreshnessLabel($0.fetchedAt, at: .now, saved: error != nil || !connected) }
        return ["Refresh \(name) details", freshness].compactMap { $0 }.joined(separator: " · ")
    }

    private func refresh() {
        if isCodex {
            viewModel.refreshUsageHistory(force: true)
            Task { await viewModel.refreshCodex() }
        } else {
            Task { await viewModel.refreshClaude() }
        }
    }
}

#if DEMO_MODE
private enum MacAnalyticsDemo {
    static let history: CodexUsageHistory? = {
        let now = Date.now
        let rows: [[String: Any]] = (0..<30).reversed().filter { $0 != 12 }.map { offset in
            let credits = Double([32, 48, 21, 64, 53, 18, 8][offset % 7])
            return ["date": CodexUsageHistory.dateString(now.addingTimeInterval(-Double(offset) * 86400)),
                    "product_surface_usage_values": ["cli": credits * 0.6, "desktop_app": credits * 0.3, "web": credits * 0.1],
                    "models": [["model": "gpt-5", "credits": credits * 0.8], ["model": "gpt-5-mini", "credits": credits * 0.2]]]
        }
        return try? CodexUsageHistory.decode(JSONSerialization.data(withJSONObject: ["data": rows]), now: now)
    }()
    static func reading(_ service: ServiceType) -> QuotaReading {
        let now = Date.now
        let formatter = ISO8601DateFormatter()
        let products: [[String: Any]] = [
            ["key": "code", "display_name": "Claude Code", "percent": 72],
            ["key": "chat", "display_name": "Chats", "percent": 21],
            ["key": "cowork", "display_name": "Cowork", "percent": 7]
        ]
        let fixture: [String: Any] = ["seven_day": ["utilization": 44],
            "seven_day_breakdown": ["as_of": formatter.string(from: now),
                "window_started_at": formatter.string(from: now.addingTimeInterval(-4 * 86400)), "rows": products]]
        let breakdown = (try? JSONSerialization.data(withJSONObject: fixture))
            .flatMap { try? ClaudeAPI.decodeUsage($0, now: now) }?.claudeBreakdown
        return QuotaReading(fetchedAt: .now, shortTerm: nil, weekly: nil,
            metadata: AccountMetadata(plan: "Demo", balanceUSD: nil, usageSpent: 12.4, usageCurrency: "USD"),
            claudeBreakdown: service == .claude ? breakdown : nil)
    }
}
#endif
