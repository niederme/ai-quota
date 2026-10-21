import SwiftUI
import UniformTypeIdentifiers
import AIQuotaKit

private struct AccountCardDropDelegate: DropDelegate {
    let destination: String
    @Binding var dragging: String?
    let move: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != destination else { return }
        move(dragging, destination)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// The open panel can show every account; its order is separate from menu-bar
/// and widget choices. Two equal columns preserve the original comparison.
struct MacAccountGridView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    let width: CGFloat
    let maxHeight: CGFloat
    let openAccount: (ConnectedAccount) -> Void
    let openSettings: () -> Void

    @State private var orderIDs: [String] = []
    @State private var dragging: String?

    private var accounts: [ConnectedAccount] {
        let visible = AccountRegistry.orderedAccounts().filter { account in
            switch account.connectionKind {
            case .legacyPrimary: viewModel.enrolledServices.contains(account.provider)
            case .isolated: viewModel.additionalAccounts.contains { $0.id == account.id }
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        let saved = orderIDs.compactMap { byID[$0] }
        let included = Set(saved.map(\.id))
        return saved + visible.filter { !included.contains($0.id) }
    }

    private var columnCount: Int { MacAccountGridLayout.columns(for: Double(width)) }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 250), spacing: 12, alignment: .top), count: columnCount)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(accounts) { account in
                    MacAccountCard(account: account, session: session(for: account),
                                   open: { openAccount(account) }, openSettings: openSettings)
                        .onDrag {
                            dragging = account.id
                            return NSItemProvider(object: account.id as NSString)
                        }
                        .onDrop(of: [UTType.plainText], delegate: AccountCardDropDelegate(
                            destination: account.id, dragging: $dragging, move: move
                        ))
                        .contextMenu {
                            Button("Move earlier") { move(account.id, offset: -1) }
                                .disabled(accounts.first?.id == account.id)
                            Button("Move later") { move(account.id, offset: 1) }
                                .disabled(accounts.last?.id == account.id)
                        }
                        .accessibilityAction(named: "Move earlier") { move(account.id, offset: -1) }
                        .accessibilityAction(named: "Move later") { move(account.id, offset: 1) }
                }
            }
            .padding(14)
        }
        .frame(width: width, height: CGFloat(MacAccountGridLayout.viewportHeight(
            accountCount: accounts.count, width: Double(width), availableHeight: Double(maxHeight)
        )))
        .scrollIndicators(.automatic)
        .onAppear { orderIDs = AccountRegistry.orderedAccounts().map(\.id) }
        .onChange(of: viewModel.additionalAccounts.map(\.id)) { _, _ in
            orderIDs = AccountRegistry.orderedAccounts().map(\.id)
        }
    }

    private func session(for account: ConnectedAccount) -> AdditionalAccountSession? {
        guard account.connectionKind == .isolated else { return nil }
        return viewModel.additionalAccounts.first { $0.id == account.id }
    }

    private func move(_ source: String, _ destination: String) {
        var ids = accounts.map(\.id)
        guard let from = ids.firstIndex(of: source), let to = ids.firstIndex(of: destination),
              from != to else { return }
        ids.remove(at: from)
        ids.insert(source, at: to)
        orderIDs = ids
        AccountRegistry.setAccountOrder(ids)
    }

    private func move(_ id: String, offset: Int) {
        let ids = accounts.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        move(id, ids[index + offset])
    }
}

private struct MacAccountCard: View {
    @Environment(QuotaViewModel.self) private var viewModel
    let account: ConnectedAccount
    let session: AdditionalAccountSession?
    let open: () -> Void
    let openSettings: () -> Void

    private var codexUsage: CodexUsage? {
        session?.codexUsage ?? (account.connectionKind == .legacyPrimary ? viewModel.codexUsage : nil)
    }
    private var claudeUsage: ClaudeUsage? {
        session?.claudeUsage ?? (account.connectionKind == .legacyPrimary ? viewModel.claudeUsage : nil)
    }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(serviceName).font(.headline.bold())
                Spacer(minLength: 4)
                Text(account.displayLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(account.displayLabel)
            }
            HStack(alignment: .top, spacing: 8) {
                gauge
                    .frame(width: 140, alignment: .center)
                VStack(alignment: .leading, spacing: 7) {
                    if let plan {
                        Text(plan)
                            .font(.callout.bold())
                            .foregroundStyle(Color.gaugeAccent)
                            .lineLimit(2)
                    }
                    if let usage = codexUsage, let balance = usage.creditBalance {
                        Text("Credits: \(balance.formatted(.number.precision(.fractionLength(0...2))))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let spend = claudeUsage?.spendLimit {
                        Text("\(spend.used.formatted(.number.precision(.fractionLength(0...2)))) of \(spend.limit.formatted(.number.precision(.fractionLength(0...2)))) monthly spend")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let issue {
                        Text(issue).font(.caption2).foregroundStyle(.orange)
                            .lineLimit(3).help(issue)
                    } else if !connected {
                        Text(loading ? "Connecting…" : "Needs connection")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let fetchedAt = codexUsage?.fetchedAt ?? claudeUsage?.fetchedAt {
                        Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            }
            HStack {
                Button(connected ? "Details" : "Reconnect", action: connected ? open : reconnect)
                Spacer()
                Button("Manage", action: openSettings)
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.medium))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 226, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(serviceName), \(account.displayLabel)")
    }

    @ViewBuilder private var gauge: some View {
        if account.provider == .codex, let usage = codexUsage {
            if let budget = usage.displayableMonthlyBudget, let used = budget.used, let limit = budget.limit {
                BudgetGaugeView(used: used, limit: limit,
                                usedText: used.formatted(.number.precision(.fractionLength(0...1))),
                                limitText: limit.formatted(.number.precision(.fractionLength(0...1))),
                                unitLabel: budget.unit ?? "monthly allowance", icon: icon,
                                label: serviceName, resetAt: budget.resetAt,
                                isRefreshing: loading, onRefresh: refresh)
            } else {
                let dual = usage.reportedWindowShape == .dual
                CircularGaugeView(
                    primaryPercent: dual ? usage.hourlyUsedPercent : usage.weeklyUsedPercent,
                    primaryLimitReached: dual ? usage.hourlyUsedPercent >= 100 : usage.isWeeklyExhausted,
                    showsPrimaryMetric: usage.reportedWindowShape != nil,
                    secondaryPercent: usage.weeklyUsedPercent,
                    secondaryLimitReached: usage.isWeeklyExhausted,
                    showsSecondaryMetric: dual, isLoading: false, icon: icon, label: serviceName,
                    primaryLabel: dual ? "5h" : "7d", secondaryLabel: "7d",
                    resetAt: dual ? usage.hourlyResetAt : usage.weeklyResetAt,
                    weeklyResetAt: usage.weeklyResetAt,
                    isRefreshing: loading, onRefresh: refresh)
            }
        } else if account.provider == .claude, let usage = claudeUsage {
            if usage.primaryMetric.kind == .spendLimit, let spend = usage.spendLimit {
                BudgetGaugeView(used: spend.used, limit: spend.limit,
                                usedText: spend.used.formatted(.number.precision(.fractionLength(0...2))),
                                limitText: spend.limit.formatted(.number.precision(.fractionLength(0...2))),
                                unitLabel: "monthly spend", icon: icon, label: serviceName,
                                resetAt: nil, isRefreshing: loading, onRefresh: refresh)
            } else {
                CircularGaugeView(
                    primaryPercent: usage.usedPercent, primaryLimitReached: usage.limitReached,
                    showsPrimaryMetric: true,
                    secondaryPercent: Int(usage.sevenDayUtilization?.rounded() ?? 0),
                    secondaryLimitReached: (usage.sevenDayUtilization ?? 0) >= 100,
                    showsSecondaryMetric: usage.primaryMetric.kind != .sevenDay && usage.sevenDayUtilization != nil,
                    isLoading: false, icon: icon, label: serviceName,
                    primaryLabel: usage.primaryMetricLabel, secondaryLabel: "7d",
                    resetAt: usage.resetAt, weeklyResetAt: usage.sevenDayResetsAt,
                    isRefreshing: loading, onRefresh: refresh)
            }
        } else {
            CircularGaugeView(
                primaryPercent: 0, primaryLimitReached: false, showsPrimaryMetric: false,
                secondaryPercent: 0, secondaryLimitReached: false, showsSecondaryMetric: false,
                isLoading: loading, icon: icon, label: serviceName,
                primaryLabel: "5h", secondaryLabel: "7d", resetAt: nil, weeklyResetAt: nil,
                isRefreshing: loading, onRefresh: refresh)
        }
    }

    private func refresh() {
        if let session { Task { await session.refresh() } }
        else { viewModel.manualRefresh() }
    }
    private func reconnect() {
        if let session { Task { await viewModel.reconnectAccount(id: session.id) } }
        else if account.provider == .codex { Task { await viewModel.signIn() } }
        else { Task { await viewModel.signInClaude() } }
    }
}
