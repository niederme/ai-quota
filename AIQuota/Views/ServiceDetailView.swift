import SwiftUI
import Charts
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
        isCodex
            ? viewModel.isCodexLoading || viewModel.isUsageHistoryLoading
            : viewModel.isClaudeLoading || viewModel.isClaudeSpendLoading || viewModel.isClaudeSkillsLoading
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
    private var showsClaudeEnterpriseDetails: Bool {
        guard !isCodex else { return false }
        return viewModel.claudeUsage?.planLabel == .enterprise
            || viewModel.claudeUsage?.spendLimit != nil
            || viewModel.claudeEnterpriseSpend != nil
            || viewModel.claudeEnterpriseSkills != nil
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
                        if showsClaudeEnterpriseDetails {
                            if viewModel.claudeDetailsNeedSignIn {
                                ClaudeEnterpriseDetailSignInView(
                                    busy: viewModel.isClaudeDetailsSignInLoading,
                                    signIn: { Task { await viewModel.signInClaudeForEnterpriseDetails() } }
                                )
                            } else {
                                ClaudeEnterpriseSpendView(
                                    snapshot: viewModel.claudeEnterpriseSpend,
                                    busy: viewModel.isClaudeSpendLoading,
                                    failed: viewModel.claudeSpendFailed,
                                    retry: { viewModel.refreshClaudeSpendDetails(force: true) }
                                )
                                ClaudeEnterpriseSkillsView(
                                    snapshot: viewModel.claudeEnterpriseSkills,
                                    currency: viewModel.claudeEnterpriseSpend?.report.currency,
                                    busy: viewModel.isClaudeSkillsLoading,
                                    failed: viewModel.claudeSkillsFailed,
                                    retry: { viewModel.refreshClaudeSkillsDetails(force: true) }
                                )
                            }
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
                                Label("Open Claude usage settings", systemImage: "arrow.up.right")
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
            if isCodex, connected {
                viewModel.refreshUsageHistory()
            } else if connected, showsClaudeEnterpriseDetails {
                viewModel.refreshClaudeEnterpriseDetails()
            }
        }
        .onChange(of: showsClaudeEnterpriseDetails) { _, showsDetails in
            if showsDetails, connected { viewModel.refreshClaudeEnterpriseDetails() }
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
            viewModel.refreshClaudeEnterpriseDetails(force: true)
            Task { await viewModel.refreshClaude() }
        }
    }
}

private struct ClaudeEnterpriseDetailSignInView: View {
    let busy: Bool
    let signIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sign in for Enterprise details", systemImage: "person.crop.circle.badge.plus")
                .font(.headline)
            Text("Claude allowance is connected. Spend history and skill activity need a matching Claude web session in AIQuota.")
                .font(.callout).foregroundStyle(AnalyticsStyle.secondary)
            Button(action: signIn) {
                if busy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Signing in…")
                    }
                } else {
                    Text("Sign in for details")
                }
            }
            .disabled(busy)
        }
        .modifier(AnalyticsCard())
    }
}

private struct ClaudeEnterpriseSpendView: View {
    let snapshot: ScopedClaudeEnterpriseSpend?
    let busy: Bool
    let failed: Bool
    let retry: () -> Void

    private struct Day: Identifiable {
        let date: Date
        let minorUnits: Int
        var id: Date { date }
    }

    private struct Product: Identifiable {
        let id: String
        let name: String
        let minorUnits: Int
        let percent: Double?
    }

    private var currency: String? {
        snapshot?.report.currency.flatMap { $0.isEmpty ? nil : $0.uppercased() }
    }

    private var days: [Day] {
        guard let snapshot else { return [] }
        var values: [Date: Int] = [:]
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for item in snapshot.report.series {
            guard let bucket = item.bucket,
                  let date = Self.date(bucket),
                  let cost = item.costMinorUnits
            else { continue }
            values[utcCalendar.startOfDay(for: date), default: 0] += cost
        }
        return values.map { Day(date: $0.key, minorUnits: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private var products: [Product] {
        guard let snapshot else { return [] }
        if !snapshot.report.totals.isEmpty {
            return snapshot.report.totals.enumerated().map { index, item in
                Product(
                    id: item.groupKey ?? item.group ?? "product-\(index)",
                    name: Self.displayName(item.group ?? item.groupKey ?? "Other"),
                    minorUnits: item.costMinorUnits ?? 0,
                    percent: item.percentOfTotal
                )
            }.sorted { $0.minorUnits > $1.minorUnits }
        }
        var values: [String: (name: String, cost: Int)] = [:]
        for (index, item) in snapshot.report.series.enumerated() {
            let key = item.groupKey ?? item.group ?? "product-\(index)"
            let name = Self.displayName(item.group ?? item.groupKey ?? "Other")
            let current = values[key] ?? (name, 0)
            values[key] = (current.name, current.cost + (item.costMinorUnits ?? 0))
        }
        let total = values.values.reduce(0) { $0 + $1.cost }
        return values.map { key, item in
            Product(
                id: key,
                name: item.name,
                minorUnits: item.cost,
                percent: total > 0 ? Double(item.cost) / Double(total) * 100 : nil
            )
        }.sorted { $0.minorUnits > $1.minorUnits }
    }

    private var totalMinorUnits: Int {
        if !products.isEmpty { return products.reduce(0) { $0 + $1.minorUnits } }
        return days.reduce(0) { $0 + $1.minorUnits }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enterprise spend").font(.headline)
            if let snapshot {
                Text(Self.money(totalMinorUnits, currency: currency))
                    .font(.largeTitle.bold()).monospacedDigit()
                Text(snapshot.period.startDate.formatted(.dateTime.month(.wide).year()))
                    .font(.footnote).foregroundStyle(AnalyticsStyle.secondary)
                if !days.isEmpty {
                    Chart(days) { day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Spend", Double(day.minorUnits) / 100)
                        )
                        .foregroundStyle(AnalyticsStyle.accent)
                        .cornerRadius(2)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) {
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                    .chartLegend(.hidden)
                    .frame(height: 150)
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                    .accessibilityLabel("Daily Enterprise spend")
                }
                if products.isEmpty {
                    Text("No product spend reported for this month.")
                        .font(.callout).foregroundStyle(AnalyticsStyle.secondary)
                } else {
                    Text("By product").font(.callout.weight(.semibold))
                    ForEach(products) { product in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(product.name).lineLimit(2)
                            Spacer(minLength: 12)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Self.money(product.minorUnits, currency: currency))
                                    .fontWeight(.semibold).monospacedDigit()
                                if let percent = product.percent {
                                    Text(percent.formatted(.number.precision(.fractionLength(0...1))) + "%")
                                        .font(.caption).foregroundStyle(AnalyticsStyle.secondary)
                                }
                            }
                        }
                    }
                }
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("Spend · " + analyticsFreshnessLabel(snapshot.fetchedAt, at: context.date, saved: failed))
                        .font(.footnote).foregroundStyle(AnalyticsStyle.secondary)
                }
                if failed {
                    Text("Couldn’t refresh spend. Last reported values remain visible.")
                        .font(.callout).foregroundStyle(AnalyticsStyle.warning)
                    Button("Retry spend", action: retry).disabled(busy)
                }
            } else if busy {
                Label("Loading Enterprise spend…", systemImage: "chart.bar")
                    .font(.callout).foregroundStyle(AnalyticsStyle.secondary)
            } else {
                Text(failed ? "Enterprise spend couldn’t be loaded." : "Enterprise spend was not reported.")
                    .font(.callout).foregroundStyle(AnalyticsStyle.secondary)
                Button("Retry spend", action: retry).disabled(busy)
            }
        }
        .modifier(AnalyticsCard())
    }

    private static func date(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func displayName(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").map(\.capitalized).joined(separator: " ")
    }

    fileprivate static func money(_ minorUnits: Int, currency: String?) -> String {
        let amount = Double(minorUnits) / 100
        if let currency, currency.count == 3 {
            return amount.formatted(.currency(code: currency))
        }
        return amount.formatted(.number.precision(.fractionLength(2)))
    }
}

private struct ClaudeEnterpriseSkillsView: View {
    let snapshot: ScopedClaudeEnterpriseSkills?
    let currency: String?
    let busy: Bool
    let failed: Bool
    let retry: () -> Void

    private var items: [(offset: Int, element: ClaudeEnterpriseSkillUsage)] {
        Array((snapshot?.report.items ?? []).enumerated()).sorted {
            ($0.element.invocationCount ?? 0) > ($1.element.invocationCount ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Skills").font(.headline)
            if let snapshot {
                if items.isEmpty {
                    Text("No skill invocations reported for this month.")
                        .font(.callout).foregroundStyle(AnalyticsStyle.secondary)
                } else {
                    ForEach(items, id: \.offset) { entry in
                        let item = entry.element
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(item.skillName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed skill")
                                    .fontWeight(.semibold).lineLimit(2)
                                Spacer(minLength: 12)
                                Text((item.invocationCount ?? 0).formatted())
                                    .monospacedDigit()
                            }
                            Text((item.invocationCount == 1 ? "1 invocation" : "\(item.invocationCount ?? 0) invocations"))
                                .font(.caption).foregroundStyle(AnalyticsStyle.secondary)
                            if let cost = item.totalCostMinorUnits {
                                Text("Total cost " + ClaudeEnterpriseSpendView.money(cost, currency: currency))
                                    .font(.caption).foregroundStyle(AnalyticsStyle.secondary)
                            } else {
                                Text("Total cost not reported")
                                    .font(.caption).foregroundStyle(AnalyticsStyle.secondary)
                            }
                            if let price = item.attributedListPriceMinorUnits {
                                Text("Attributed list price " + ClaudeEnterpriseSpendView.money(price, currency: currency))
                                    .font(.caption).foregroundStyle(AnalyticsStyle.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("Skills · " + analyticsFreshnessLabel(snapshot.fetchedAt, at: context.date, saved: failed))
                        .font(.footnote).foregroundStyle(AnalyticsStyle.secondary)
                }
                if snapshot.report.hasMore == true {
                    Text("Claude reports additional skills beyond this list.")
                        .font(.footnote).foregroundStyle(AnalyticsStyle.secondary)
                }
                if failed {
                    Text("Couldn’t refresh skills. Last reported values remain visible.")
                        .font(.callout).foregroundStyle(AnalyticsStyle.warning)
                    Button("Retry skills", action: retry).disabled(busy)
                }
            } else if busy {
                Label("Loading skill activity…", systemImage: "wand.and.stars")
                    .font(.callout).foregroundStyle(AnalyticsStyle.secondary)
            } else {
                Text(failed ? "Skill activity couldn’t be loaded." : "Skill activity was not reported.")
                    .font(.callout).foregroundStyle(AnalyticsStyle.secondary)
                Button("Retry skills", action: retry).disabled(busy)
            }
        }
        .modifier(AnalyticsCard())
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
