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
    private var name: String { service.displayName }
    private var logo: String {
        switch service {
        case .codex:  "logo-openai"
        case .claude: "logo-claude"
        case .devin:  "logo-devin"
        }
    }
    private var busy: Bool {
        switch service {
        case .codex:  viewModel.isCodexLoading || viewModel.isUsageHistoryLoading
        case .claude: viewModel.isClaudeLoading
        case .devin:  viewModel.isDevinLoading
        }
    }
    private var connected: Bool {
        switch service {
        case .codex:  viewModel.isCodexAuthenticated
        case .claude: viewModel.isClaudeAuthenticated
        case .devin:  viewModel.isDevinAuthenticated
        }
    }
    private var error: NetworkError? {
        switch service {
        case .codex:  viewModel.codexError
        case .claude: viewModel.claudeError
        case .devin:  viewModel.devinError
        }
    }
    private var reading: QuotaReading? {
        #if DEMO_MODE
        return MacAnalyticsDemo.reading(service)
        #else
        switch service {
        case .codex:
            guard let usage = viewModel.codexUsage else { return nil }
            return QuotaReading(fetchedAt: usage.fetchedAt, shortTerm: nil, weekly: nil,
                metadata: AccountMetadata(plan: usage.planType, balanceUSD: usage.creditBalance,
                    usageSpent: usage.bonusCreditsSpentThisMonth.map { $0 / 25 }, usageCurrency: "USD"))
        case .claude:
            guard let usage = viewModel.claudeUsage else { return nil }
            return QuotaReading(fetchedAt: usage.fetchedAt, shortTerm: nil, weekly: nil,
                metadata: AccountMetadata(plan: usage.planDisplayName, balanceUSD: nil,
                    usageSpent: usage.usageCredits?.spent, usageCurrency: usage.usageCredits?.currencyCode),
                claudeBreakdown: usage.weeklyBreakdown)
        case .devin:
            guard let usage = viewModel.devinUsage else { return nil }
            return DevinAPI.makeReading(from: usage)
        }
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
                Image(logo)
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
                        switch service {
                        case .codex:
                            CodexAnalyticsView(reading: reading, history: history,
                                historyUnavailable: viewModel.usageHistoryFailed,
                                busy: busy, refresh: refresh)
                        case .claude:
                            ClaudeAnalyticsView(reading: reading, busy: busy, failed: error != nil || !connected, refresh: refresh)
                        case .devin:
                            DevinAnalyticsView(reading: reading, busy: busy, refresh: refresh)
                        }
                        if let error {
                            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                                .font(.callout).foregroundStyle(Color.warningAmber)
                        }
                        Divider()
                        Button(action: openAccount) {
                            Label(connected ? "Account and connection" : "Connect \(name)", systemImage: "person.crop.circle")
                        }
                        if isCodex {
                            Button { NSWorkspace.shared.open(CodexResetNotice.website) } label: {
                                Label("Check Codex resets", systemImage: "arrow.up.right")
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
        switch service {
        case .codex:
            viewModel.refreshUsageHistory(force: true)
            Task { await viewModel.refreshCodex() }
        case .claude:
            Task { await viewModel.refreshClaude() }
        case .devin:
            Task { await viewModel.refreshDevin() }
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
