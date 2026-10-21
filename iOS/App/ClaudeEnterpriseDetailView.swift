import Charts
import SwiftUI
import MobileAccessCore

/// Native Claude Enterprise analytics. A missing web session is handled by a
/// single, reversible Claude reconnect prompt, not a second connection card.
struct ClaudeEnterpriseDetailView: View {
    let account: ClaudeProbeModel
    private let organizationLookup: @MainActor () async -> ClaudeOrganizationLookup
    private var session: ClaudeWebDetailsSession { account.webDetailsSession }
    @State private var lookupGeneration = UUID()
    @State private var showSignIn = false
    @State private var showPopup = false
    @State private var showAccountReconnect = false
    @State private var showReconnectPrompt = false
    @State private var reconnectExplanation = ""
    @State private var reconnectGate = ClaudeReconnectPromptGate()

    init(account: ClaudeProbeModel,
         organizationLookup: (@MainActor () async -> ClaudeOrganizationLookup)? = nil) {
        self.account = account
        self.organizationLookup = organizationLookup ?? { await account.organizationLookup() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch session.state {
            case .idle, .checking:
                loadingRow("Loading Claude details…")
            case .awaitingSignIn:
                loadingRow("Waiting for Claude sign-in…")
            case .signInRequired, .accountMismatch:
                reconnectRow("Claude sign-in required")
            case .organizationReconnectRequired:
                reconnectRow("Claude account verification needed")
            case .unavailable:
                compactUnavailable("Claude details unavailable")
            case .ready:
                if session.detailsLoading && session.spend == nil && session.skills == nil {
                    loadingRow("Loading spend and skills…")
                }
                if let spend = session.spend, !spend.series.isEmpty || !spend.totals.isEmpty {
                    spendCard(spend)
                } else if session.spendUnavailable {
                    compactUnavailable("Spend history unavailable")
                }
                if let skills = session.skills, !skills.items.isEmpty {
                    skillsCard(skills, currency: session.spend?.currency ?? "USD")
                } else if session.skillsUnavailable {
                    compactUnavailable("Skill details unavailable")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await retry() }
        .sheet(isPresented: $showAccountReconnect) {
            ServiceAccountSheet { ClaudeProbeView(model: account) }
        }
        .sheet(isPresented: $showSignIn, onDismiss: {
            Task {
                let wasReady = session.state == .ready
                if !wasReady {
                    await session.cancelReconnect()
                    await retry(force: true)
                }
            }
        }) {
            NavigationStack {
                VStack(spacing: 0) {
                    ClaudeWebSurface(webView: session.webView)
                    if session.state != .ready {
                        HStack(spacing: 12) {
                            if session.state == .accountMismatch || session.state == .unavailable {
                                Text(session.state == .accountMismatch
                                     ? "Use the Claude account for this Enterprise organization."
                                     : "Couldn’t verify this sign-in.")
                                    .font(.footnote)
                            }
                            Spacer(minLength: 0)
                            Button("Check sign-in") { session.refresh() }
                                .font(.footnote.weight(.semibold))
                        }
                        .padding(12)
                        .background(OverviewStyle.track)
                    }
                }
                    .navigationTitle("Sign in to Claude")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") { showSignIn = false }
                    } }
            }
            .sheet(isPresented: $showPopup) {
                if let popup = session.popup {
                    NavigationStack {
                        ClaudeWebSurface(webView: popup)
                            .navigationTitle("Continue sign-in")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                                Button("Close") { session.webViewDidClose(popup); showPopup = false }
                            } }
                    }
                }
            }
        }
        .onChange(of: session.popup) { _, popup in showPopup = popup != nil }
        .onChange(of: account.signInCompletionID) { _, _ in Task { await retry() } }
        .onChange(of: session.state) { _, state in
            if state == .ready { showSignIn = false }
            if reconnectGate.shouldPrompt(for: state, signInVisible: showSignIn) {
                reconnectExplanation = switch state {
                case .accountMismatch:
                    "This Claude sign-in belongs to another organization. Sign in with the Enterprise organization shown in your allowance? Cancel keeps your connection."
                case .organizationReconnectRequired:
                    "Claude’s current account connection did not provide an organization to verify against the allowance. Reconnect the account to check Enterprise details. Your saved allowance stays in place."
                default:
                    "Claude requires a web sign-in for Enterprise spend and skills. Sign in to show those details? Cancel keeps your connection."
                }
                showReconnectPrompt = true
            }
        }
        .alert("Reconnect Claude", isPresented: $showReconnectPrompt) {
            Button("Cancel", role: .cancel) { }
            Button("Reconnect", action: reconnect)
        } message: { Text(reconnectExplanation) }
    }

    private func compactUnavailable(_ title: String) -> some View {
        HStack {
            Text(title).font(.callout).foregroundStyle(OverviewStyle.secondary)
            Spacer()
            Button("Retry") { Task { await retry(force: true) } }.font(.callout)
        }
        .padding(16)
        .modifier(OverviewCardMaterial())
    }

    private struct DailySpend: Identifiable {
        let day: String
        let group: String
        let amount: Double
        var id: String { day + "\0" + group }
    }

    private func spendCard(_ spend: ClaudeSpendHistory) -> some View {
        let daily = spend.series.compactMap { row -> DailySpend? in
            guard let day = row.bucket, let group = row.group, let amount = row.costMinorUnits else { return nil }
            return DailySpend(day: day, group: group, amount: Double(amount) / 100)
        }
        let highestDay = Dictionary(grouping: daily, by: \.day).values
            .map { $0.reduce(0) { $0 + $1.amount } }.max() ?? 0
        return VStack(alignment: .leading, spacing: 18) {
            Text("Daily spend by product").font(.headline)
            if !daily.isEmpty {
                Chart(daily) { value in
                    BarMark(x: .value("Day", value.day), y: .value("Spend", value.amount))
                        .foregroundStyle(by: .value("Product", value.group))
                }
                .chartYScale(domain: 0...max(1, highestDay * 1.15))
                .frame(height: 180)
                .accessibilityLabel("Daily spend by product")
            }
            HStack {
                Text("Product").frame(maxWidth: .infinity, alignment: .leading)
                Text("Spend")
                Text("% of total").frame(width: 70, alignment: .trailing)
            }.font(.caption).foregroundStyle(OverviewStyle.secondary)
            ForEach(Array(spend.totals.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.group ?? row.groupKey ?? "Other").frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.costMinorUnits.map { money($0, currency: spend.currency ?? "USD") } ?? "—").monospacedDigit()
                    Text(row.percentOfTotal.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? "—")
                        .monospacedDigit().frame(width: 70, alignment: .trailing)
                }.font(.callout)
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .modifier(OverviewCardMaterial())
    }

    private func skillsCard(_ skills: ClaudeEnterpriseSkillsResponse, currency: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Top skills").font(.headline)
            HStack {
                Text("Skill").frame(maxWidth: .infinity, alignment: .leading)
                Text("Cost per use").frame(width: 90, alignment: .trailing)
                Text("Uses").frame(width: 45, alignment: .trailing)
            }.font(.caption).foregroundStyle(OverviewStyle.secondary)
            ForEach(Array(skills.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline) {
                    Text(item.skillName ?? "Unknown skill").lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.totalCostMinorUnits.flatMap { cost in
                        item.invocationCount.flatMap { $0 > 0 ? moneyPerUse(cost, uses: $0, currency: currency) : nil }
                    } ?? "—")
                        .monospacedDigit().frame(width: 90, alignment: .trailing)
                    Text(item.invocationCount?.formatted() ?? "—").monospacedDigit().frame(width: 45, alignment: .trailing)
                }.font(.callout)
                Divider()
            }
            if skills.hasMore == true { Text("Showing top skills").font(.footnote).foregroundStyle(OverviewStyle.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .modifier(OverviewCardMaterial())
    }

    private func money(_ minor: Int, currency: String) -> String {
        (Double(minor) / 100).formatted(.currency(code: currency))
    }

    private func moneyPerUse(_ minor: Int, uses: Int, currency: String) -> String {
        (Double(minor) / Double(uses) / 100).formatted(.currency(code: currency))
    }

    private func reconnectRow(_ title: String) -> some View {
        HStack {
            Text(title).font(.callout).foregroundStyle(OverviewStyle.secondary)
            Spacer()
            Button("Reconnect", action: reconnect).font(.callout)
        }
        .padding(16)
        .modifier(OverviewCardMaterial())
    }

    private func reconnect() {
        lookupGeneration = UUID()
        if session.state == .organizationReconnectRequired {
            account.connect()
            showAccountReconnect = true
        } else {
            Task { await session.beginReconnect(); showSignIn = true }
        }
    }

    private func retry(force: Bool = false) async {
        let id = UUID()
        lookupGeneration = id
        let organization = await organizationLookup()
        guard lookupGeneration == id, !showSignIn else { return }
        session.start(organization: organization, reuseReady: !force)
    }

    private func loadingRow(_ title: String) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            ProgressView().controlSize(.small)
            Text(title).font(.callout).foregroundStyle(OverviewStyle.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
    }
}

/// Limits automatic reconnect prompts to one per detail visit. A transient
/// service failure and navigation within the login sheet never trigger one.
struct ClaudeReconnectPromptGate {
    private(set) var hasPrompted = false

    mutating func shouldPrompt(for state: ClaudeWebDetailsSession.State, signInVisible: Bool) -> Bool {
        guard !hasPrompted, !signInVisible,
              state == .signInRequired || state == .accountMismatch
                || state == .organizationReconnectRequired else { return false }
        hasPrompted = true
        return true
    }
}
