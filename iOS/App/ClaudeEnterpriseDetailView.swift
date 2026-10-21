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
    @State private var selectedSpendDay: String?
    @State private var showsAllSkills = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                    skillsCard(
                        skills,
                        currency: session.spend?.currency ?? "USD",
                        reportingEndDate: session.spend?.endDate ?? session.requestedEndDate
                    )
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
        let productID: String
        let productName: String
        let minorUnits: Int
        var id: String { day + "\0" + productID }
    }

    private struct ProductSpend: Identifiable {
        let id: String
        let name: String
        let minorUnits: Int?
        let percent: Double?
    }

    private func spendCard(_ spend: ClaudeSpendHistory) -> some View {
        let daily = spend.series.compactMap { row -> DailySpend? in
            guard let day = row.bucket, ClaudeEnterpriseDateOnly.bucketDate(day) != nil,
                  let amount = row.costMinorUnits else { return nil }
            let key = row.groupKey ?? row.group ?? "other"
            return DailySpend(
                day: String(day.prefix(10)),
                productID: key,
                productName: productName(group: row.group, key: row.groupKey),
                minorUnits: amount
            )
        }
        let products = productTotals(spend, daily: daily)
        let knownProductAmounts = products.compactMap(\.minorUnits)
        let totalMinorUnits = knownProductAmounts.isEmpty ? nil : knownProductAmounts.reduce(0, +)
        let chartDays = reportDays(spend, daily: daily)
        let highestDay = Dictionary(grouping: daily, by: \.day).values
            .map { $0.reduce(0) { $0 + $1.minorUnits } }.max() ?? 0
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Spend by product").font(.headline)
                Text(totalMinorUnits.map { money($0, currency: spend.currency ?? "USD") } ?? "—")
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                if let period = reportingPeriod(spend) {
                    Text(period).font(.footnote).foregroundStyle(OverviewStyle.secondary)
                }
            }
            if !daily.isEmpty {
                Chart(daily) { value in
                    BarMark(
                        x: .value("Day", value.day),
                        y: .value("Spend", Double(value.minorUnits) / 100)
                    )
                    .foregroundStyle(by: .value("Product", value.productName))
                    .cornerRadius(2)
                    .accessibilityLabel("\(value.productName), \(displayDate(value.day))")
                    .accessibilityValue(money(value.minorUnits, currency: spend.currency ?? "USD"))
                }
                .chartYScale(domain: 0...max(1, Double(highestDay) / 100 * 1.15))
                .chartXScale(domain: chartDays)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let day = value.as(String.self) { Text(axisDate(day)) }
                        }
                    }
                }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .chartForegroundStyleScale(
                    domain: products.map(\.name),
                    range: products.map { productColor(id: $0.id, name: $0.name) }
                )
                .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
                .chartXSelection(value: $selectedSpendDay)
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 260 : 220)
                .accessibilityLabel("Daily spend by product")
                .accessibilityHint("Tap a day to show its product amounts")
            }
            if let selectedSpendDay,
               chartDays.contains(selectedSpendDay) {
                selectedDayDetail(selectedSpendDay, daily: daily, currency: spend.currency ?? "USD")
            }
            Text("By product").font(.callout.weight(.semibold))
            ForEach(products) { product in
                productRow(product, currency: spend.currency ?? "USD")
                if product.id != products.last?.id { Divider() }
            }
            Text("Source: Claude Enterprise analytics")
                .font(.footnote)
                .foregroundStyle(OverviewStyle.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .modifier(OverviewCardMaterial())
    }

    private func skillsCard(
        _ skills: ClaudeEnterpriseSkillsResponse,
        currency: String,
        reportingEndDate: String?
    ) -> some View {
        let visibleCount = showsAllSkills ? skills.items.count : min(5, skills.items.count)
        let visibleItems = Array(skills.items.prefix(visibleCount).enumerated())
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Skills").font(.headline)
                if let cutoff = skillsCutoff(skills, fallbackEndDate: reportingEndDate) {
                    Text("Through \(cutoff) · UTC")
                        .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                }
            }
            ForEach(visibleItems, id: \.offset) { entry in
                let item = entry.element
                skillRow(item, currency: currency)
                if entry.offset != visibleItems.last?.offset {
                    Divider()
                }
            }
            if skills.items.count > 5 {
                Button {
                    withAnimation(.snappy) { showsAllSkills.toggle() }
                } label: {
                    HStack {
                        Text(showsAllSkills ? "Show less" : "Show more")
                        Spacer()
                        Image(systemName: showsAllSkills ? "chevron.up" : "chevron.down")
                    }
                    .font(.callout.weight(.semibold))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(showsAllSkills ? "Collapses the skill list" : "Shows every loaded skill")
            }
            if skills.hasMore == true {
                Text("Claude reports additional skills beyond the loaded list.")
                    .font(.footnote).foregroundStyle(OverviewStyle.secondary)
            }
            Text("Source: Claude Enterprise skill activity")
                .font(.footnote)
                .foregroundStyle(OverviewStyle.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .modifier(OverviewCardMaterial())
    }

    private func productTotals(_ spend: ClaudeSpendHistory, daily: [DailySpend]) -> [ProductSpend] {
        if !spend.totals.isEmpty {
            return spend.totals.enumerated().map { index, row in
                ProductSpend(
                    id: row.groupKey ?? row.group ?? "product-\(index)",
                    name: productName(group: row.group, key: row.groupKey),
                    minorUnits: row.costMinorUnits,
                    percent: row.percentOfTotal
                )
            }.sorted { ($0.minorUnits ?? Int.min) > ($1.minorUnits ?? Int.min) }
        }
        let grouped = Dictionary(grouping: daily, by: \.productID)
        let total = daily.reduce(0) { $0 + $1.minorUnits }
        return grouped.map { key, rows in
            let amount = rows.reduce(0) { $0 + $1.minorUnits }
            return ProductSpend(
                id: key,
                name: rows.first?.productName ?? productName(group: nil, key: key),
                minorUnits: amount,
                percent: total > 0 ? Double(amount) / Double(total) * 100 : nil
            )
        }.sorted { ($0.minorUnits ?? Int.min) > ($1.minorUnits ?? Int.min) }
    }

    @ViewBuilder private func productRow(_ product: ProductSpend, currency: String) -> some View {
        let details = VStack(alignment: .trailing, spacing: 2) {
            Text(product.minorUnits.map { money($0, currency: currency) } ?? "—")
                .fontWeight(.semibold).monospacedDigit()
            Text(product.percent.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "% of total" }
                 ?? "Percentage unavailable")
                .font(.caption).foregroundStyle(OverviewStyle.secondary)
        }
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(productColor(id: product.id, name: product.name))
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                    Text(product.name).font(.callout)
                }
                details.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(productColor(id: product.id, name: product.name))
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                    Text(product.name).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                details
            }
        }
    }

    @ViewBuilder private func skillRow(_ item: ClaudeEnterpriseSkillUsage, currency: String) -> some View {
        let uses = item.invocationCount
        let perUse = item.totalCostMinorUnits.flatMap { cost in
            uses.flatMap { $0 > 0 ? moneyPerUse(cost, uses: $0, currency: currency) : nil }
        }
        let metrics = VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            Text("Cost per use \(perUse ?? "—")").monospacedDigit()
            Text(uses.map { "\($0.formatted()) \($0 == 1 ? "use" : "uses")" } ?? "Uses —")
        }
        .font(.caption)
        .foregroundStyle(OverviewStyle.secondary)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.skillName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown skill")
                    .font(.callout.weight(.semibold))
                metrics
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(item.skillName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown skill")
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                metrics
            }
        }
    }

    private func selectedDayDetail(_ day: String, daily: [DailySpend], currency: String) -> some View {
        let rows = daily.filter { $0.day == day }.sorted { $0.minorUnits > $1.minorUnits }
        let total = rows.reduce(0) { $0 + $1.minorUnits }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayDate(day)).font(.callout.weight(.semibold))
                Spacer()
                Text(money(total, currency: currency)).font(.callout.weight(.semibold)).monospacedDigit()
            }
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.productName).foregroundStyle(OverviewStyle.secondary)
                    Spacer()
                    Text(money(row.minorUnits, currency: currency)).monospacedDigit()
                }.font(.caption)
            }
            if rows.isEmpty {
                Text("No spend reported")
                    .font(.caption)
                    .foregroundStyle(OverviewStyle.secondary)
            }
        }
        .padding(12)
        .background(OverviewStyle.track, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func reportingPeriod(_ spend: ClaudeSpendHistory) -> String? {
        guard let start = spend.startDate ?? session.requestedStartDate,
              let end = spend.endDate ?? session.requestedEndDate else { return nil }
        return ClaudeEnterpriseDateOnly.displayRange(startDate: start, endDate: end)
    }

    private func reportDays(_ spend: ClaudeSpendHistory, daily: [DailySpend]) -> [String] {
        guard !daily.isEmpty,
              let startValue = spend.startDate ?? session.requestedStartDate ?? daily.map(\.day).min(),
              let endValue = spend.endDate ?? session.requestedEndDate ?? daily.map(\.day).max(),
              let start = ClaudeEnterpriseDateOnly.bucketDate(startValue),
              let end = ClaudeEnterpriseDateOnly.bucketDate(endValue), start <= end else {
            return Array(Set(daily.map(\.day))).sorted()
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var days: [String] = []
        var day = start
        while day <= end, days.count < 31 {
            days.append(dateKey(day, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    private func dateKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func skillsCutoff(_ skills: ClaudeEnterpriseSkillsResponse, fallbackEndDate: String?) -> String? {
        guard let end = skills.endDate ?? fallbackEndDate,
              let previous = ClaudeEnterpriseDateOnly.dayBefore(end) else { return nil }
        return ClaudeEnterpriseDateOnly.displayDate(previous)
    }

    private func displayDate(_ value: String) -> String {
        ClaudeEnterpriseDateOnly.displayDate(value) ?? value
    }

    private func axisDate(_ value: String) -> String {
        guard let date = ClaudeEnterpriseDateOnly.displayDate(value) else { return value }
        return String(date.split(separator: ",", maxSplits: 1).first ?? Substring(date))
    }

    private func productName(group: String?, key: String?) -> String {
        if let group, !group.isEmpty { return group }
        let rawKey = key ?? "Other"
        let normalized = rawKey.lowercased().replacingOccurrences(of: "-", with: "_")
        if normalized.contains("chat_and_cowork_unified") {
            return normalized.contains("beta") ? "Chat and Cowork unified (beta)" : "Chat and Cowork unified"
        }
        let words = rawKey
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
        return words.enumerated().map { index, word in
            let lower = word.lowercased()
            if index > 0, ["and", "or", "with"].contains(lower) { return lower }
            if lower == "claude" { return "Claude" }
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    private func productColor(id: String, name: String) -> Color {
        let value = (id + " " + name).lowercased().replacingOccurrences(of: "_", with: " ")
        if value.contains("claude code") { return .orange }
        if value.contains("chat and cowork") || value.contains("unified") { return .blue }
        if value.contains("cowork") { return .yellow }
        if value.contains("claude design") || value.contains("design") { return .green }
        if value.contains("chat") { return .blue }
        return OverviewStyle.accent
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
