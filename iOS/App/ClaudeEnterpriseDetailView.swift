import Charts
import SwiftUI
import MobileAccessCore

/// Native Claude Enterprise analytics. The OAuth allowance remains visible
/// independently when the web detail session is unavailable.
struct ClaudeEnterpriseDetailView: View {
    let account: ClaudeProbeModel
    @State private var session = ClaudeWebDetailsSession()
    @State private var showSignIn = false
    @State private var showPopup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch session.state {
            case .idle, .checking:
                ProgressView("Loading Claude details…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .signInRequired:
                connectionCard("Connect Claude details", detail: "Sign in to Claude to see spend by product and top skills here.")
            case .accountMismatch:
                connectionCard("Different Claude account", detail: "Sign in with the same Enterprise organization as your allowance.")
            case .unavailable:
                connectionCard("Claude details unavailable", detail: "Couldn’t verify the Claude web session. Try again.")
            case .ready:
                if session.detailsLoading && session.spend == nil && session.skills == nil {
                    ProgressView("Loading spend and skills…")
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        .task { session.start(expectedOrganizationID: await account.organizationID()) }
        .sheet(isPresented: $showSignIn) {
            NavigationStack {
                ClaudeWebSurface(webView: session.webView)
                    .navigationTitle("Sign in to Claude")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showSignIn = false; session.refresh() }
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
        .onChange(of: session.state) { _, state in
            if state == .ready { showSignIn = false }
        }
    }

    private func connectionCard(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(OverviewStyle.secondary)
            HStack {
                if session.state == .signInRequired || session.state == .accountMismatch {
                    Button("Sign in to Claude") { showSignIn = true; session.signIn() }
                        .buttonStyle(.borderedProminent)
                }
                Button("Try again") { retry() }.buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .modifier(OverviewCardMaterial())
    }

    private func compactUnavailable(_ title: String) -> some View {
        HStack {
            Text(title).font(.callout).foregroundStyle(OverviewStyle.secondary)
            Spacer()
            Button("Retry") { session.refresh() }.font(.callout)
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

    private func retry() {
        Task { session.start(expectedOrganizationID: await account.organizationID()) }
    }
}
