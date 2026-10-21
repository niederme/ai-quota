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
            : viewModel.isClaudeLoading || viewModel.isClaudeSpendLoading
                || viewModel.isClaudeSkillsLoading || viewModel.isClaudeEnterpriseReconnectLoading
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
    private var canFetchClaudeDetails: Bool {
        connected && viewModel.claudeUsage?.source != nil
            && viewModel.claudeUsage?.source != .unknown
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
                        if isCodex, connected {
                            CodexAnalyticsView(reading: reading, history: history,
                                historyUnavailable: viewModel.usageHistoryFailed,
                                busy: busy || (history == nil && !viewModel.usageHistoryFailed), refresh: refresh)
                        } else if !isCodex, reading?.claudeBreakdown != nil {
                            ClaudeAnalyticsView(reading: reading, busy: busy, failed: error != nil || !connected, refresh: refresh)
                        }
                        if showsClaudeEnterpriseDetails {
                            ClaudeEnterpriseSpendView(
                                snapshot: viewModel.claudeEnterpriseSpend,
                                busy: viewModel.isClaudeSpendLoading
                                    || (canFetchClaudeDetails && viewModel.claudeEnterpriseSpend == nil
                                        && !viewModel.claudeSpendFailed),
                                failed: viewModel.claudeSpendFailed,
                                retry: { viewModel.refreshClaudeSpendDetails(force: true) }
                            )
                            ClaudeEnterpriseSkillsView(
                                snapshot: viewModel.claudeEnterpriseSkills,
                                currency: viewModel.claudeEnterpriseSpend?.report.currency,
                                busy: viewModel.isClaudeSkillsLoading
                                    || (canFetchClaudeDetails && viewModel.claudeEnterpriseSkills == nil
                                        && !viewModel.claudeSkillsFailed),
                                failed: viewModel.claudeSkillsFailed,
                                retry: { viewModel.refreshClaudeSkillsDetails(force: true) }
                            )
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
        .onAppear { viewModel.beginClaudeEnterpriseDetailsPresentation() }
        .onDisappear { viewModel.dismissClaudeEnterpriseReconnectPrompt() }
        .alert(
            "Reconnect Claude for Enterprise details?",
            isPresented: Binding(
                get: { viewModel.isClaudeEnterpriseReconnectPromptPresented },
                set: { presented in
                    if !presented { viewModel.dismissClaudeEnterpriseReconnectPrompt() }
                }
            )
        ) {
            Button("Reconnect") {
                Task { await viewModel.reconnectClaudeForEnterpriseDetails() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.dismissClaudeEnterpriseReconnectPrompt()
            }
        } message: {
            Text("Your current Claude connection can still show allowance. Enterprise spend and skill activity need a Claude web session for the same organization. Reconnect opens Claude sign-in and changes the connection only after verification. Cancel keeps the current connection.")
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

private struct ClaudeEnterpriseSpendView: View {
    let snapshot: ScopedClaudeEnterpriseSpend?
    let busy: Bool
    let failed: Bool
    let retry: () -> Void

    @State private var hoveredDayID: String?

    private struct Day: Identifiable {
        let id: String
        let date: Date
        let minorUnits: Int?
        let segments: [Segment]
    }

    private struct Segment: Identifiable {
        let bucket: String
        let date: Date
        let productID: String
        let productName: String
        let minorUnits: Int

        var id: String { "\(bucket)::\(productID)" }
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

    private var segments: [Segment] {
        guard let snapshot else { return [] }
        var values: [String: Segment] = [:]
        for item in snapshot.report.series {
            guard let bucket = item.bucket,
                  let date = ClaudeEnterpriseDateOnly.bucketDate(bucket),
                  let cost = item.costMinorUnits,
                  cost >= 0
            else { continue }
            let productID = item.groupKey ?? item.group ?? "other"
            let key = "\(bucket)::\(productID)"
            let name = Self.productName(group: item.group, key: item.groupKey)
            let previous = values[key]?.minorUnits ?? 0
            values[key] = Segment(
                bucket: bucket,
                date: date,
                productID: productID,
                productName: name,
                minorUnits: previous + cost
            )
        }
        let productOrder = products.enumerated().reduce(into: [String: Int]()) {
            $0[$1.element.id] = $1.offset
        }
        return values.values.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return (productOrder[$0.productID] ?? .max) < (productOrder[$1.productID] ?? .max)
        }
    }

    private var days: [Day] {
        let reportedDays: [Day] = Dictionary(grouping: segments, by: \.bucket).values.compactMap { segments in
            guard let first = segments.first else { return nil }
            return Day(
                id: first.bucket,
                date: first.date,
                minorUnits: segments.reduce(0) { $0 + $1.minorUnits },
                segments: segments.sorted { $0.minorUnits > $1.minorUnits }
            )
        }.sorted { $0.date < $1.date }
        guard !reportedDays.isEmpty, let snapshot,
              let start = ClaudeEnterpriseDateOnly.bucketDate(
                snapshot.report.startDate ?? snapshot.period.apiStartDate
              ),
              let end = ClaudeEnterpriseDateOnly.bucketDate(
                snapshot.report.endDate ?? snapshot.period.apiEndDate
              ),
              start <= end
        else { return reportedDays }

        var reportedByDate: [Date: Day] = [:]
        for day in reportedDays { reportedByDate[day.date] = day }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var result: [Day] = []
        var date = start
        while date <= end, result.count < 370 {
            result.append(reportedByDate[date] ?? Day(
                id: Self.bucketID(date), date: date, minorUnits: nil, segments: []
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return result
    }

    private var products: [Product] {
        guard let snapshot else { return [] }
        if !snapshot.report.totals.isEmpty {
            let reportedTotals: [Product] = snapshot.report.totals.enumerated().compactMap { index, item in
                guard let minorUnits = item.costMinorUnits else { return nil }
                return Product(
                    id: item.groupKey ?? item.group ?? "product-\(index)",
                    name: Self.productName(group: item.group, key: item.groupKey),
                    minorUnits: minorUnits,
                    percent: item.percentOfTotal
                )
            }.sorted { $0.minorUnits > $1.minorUnits }
            if !reportedTotals.isEmpty { return reportedTotals }
        }
        var values: [String: (name: String, cost: Int)] = [:]
        for (index, item) in snapshot.report.series.enumerated() {
            guard let cost = item.costMinorUnits else { continue }
            let key = item.groupKey ?? item.group ?? "product-\(index)"
            let name = Self.productName(group: item.group, key: item.groupKey)
            let current = values[key] ?? (name, 0)
            values[key] = (current.name, current.cost + cost)
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
        return days.compactMap(\.minorUnits).reduce(0, +)
    }

    private var hasReportedSpend: Bool { !products.isEmpty || !segments.isEmpty }

    private var periodLabel: String? {
        if let snapshot,
           let start = snapshot.report.startDate,
           let end = snapshot.report.endDate,
           let reportRange = ClaudeEnterpriseDateOnly.displayRange(startDate: start, endDate: end) {
            return reportRange
        }
        return snapshot?.period.rangeLabel
    }

    private var hoveredDay: Day? {
        days.first { $0.id == hoveredDayID }
    }

    private var hoverAlignment: Alignment {
        guard let hoveredDay, let first = days.first, let last = days.last else { return .topTrailing }
        let midpoint = first.date.addingTimeInterval(last.date.timeIntervalSince(first.date) / 2)
        return hoveredDay.date >= midpoint ? .topLeading : .topTrailing
    }

    private var chartDomain: ClosedRange<Date> {
        let first = days.first?.date ?? segments[0].date
        let last = days.last?.date ?? segments[0].date
        return first.addingTimeInterval(-12 * 60 * 60)...last.addingTimeInterval(12 * 60 * 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Analytics spend").font(.headline)
            if let snapshot {
                if hasReportedSpend {
                    Text(Self.money(totalMinorUnits, currency: currency))
                        .font(.largeTitle.bold()).monospacedDigit()
                    Text(periodLabel ?? "Current reporting period · UTC")
                        .font(.footnote).foregroundStyle(AnalyticsStyle.secondary)
                } else {
                    Text(periodLabel ?? "Current reporting period · UTC")
                        .font(.footnote).foregroundStyle(AnalyticsStyle.secondary)
                    Text("Spend amounts were not reported for this period.")
                        .font(.callout).foregroundStyle(AnalyticsStyle.secondary)
                }
                if hasReportedSpend, !segments.isEmpty {
                    ZStack(alignment: hoverAlignment) {
                        Chart(segments) { segment in
                        BarMark(
                            x: .value("Day", segment.date, unit: .day),
                            y: .value("Spend", Double(segment.minorUnits) / 100),
                            stacking: .standard
                        )
                        .foregroundStyle(productColor(segment.productID))
                        .cornerRadius(2)
                        .accessibilityLabel(
                            "\(ClaudeEnterpriseDateOnly.displayDate(segment.bucket) ?? segment.bucket), \(segment.productName)"
                        )
                        .accessibilityValue(Self.money(segment.minorUnits, currency: currency))
                    }
                    .chartXAxis {
                        AxisMarks(values: axisDates) {
                            AxisGridLine()
                            AxisTick()
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                    .chartXScale(domain: chartDomain)
                    .chartLegend(.hidden)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        guard let plotFrame = proxy.plotFrame else {
                                            hoveredDayID = nil
                                            return
                                        }
                                        let frame = geometry[plotFrame]
                                        let x = location.x - frame.minX
                                        guard x >= 0, x <= frame.width,
                                              let date: Date = proxy.value(atX: x)
                                        else {
                                            hoveredDayID = nil
                                            return
                                        }
                                        hoveredDayID = days.min {
                                            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                        }?.id
                                    case .ended:
                                        hoveredDayID = nil
                                    }
                                }
                        }
                    }
                    .frame(height: 168)
                    .environment(\.calendar, utcChartCalendar)
                    .environment(\.timeZone, utcChartCalendar.timeZone)
                    .accessibilityLabel("Daily Enterprise spend by product in UTC")
                    .accessibilityValue(Self.money(totalMinorUnits, currency: currency))

                        if let hoveredDay {
                            dayPopover(hoveredDay)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    chartDateLabels
                    Text(chartCoverageLabel)
                        .font(.footnote)
                        .foregroundStyle(AnalyticsStyle.secondary)
                }
                if hasReportedSpend, products.isEmpty {
                    Text("No product spend reported for this month.")
                        .font(.callout).foregroundStyle(AnalyticsStyle.secondary)
                } else if hasReportedSpend {
                    Text("Spend by product").font(.callout.weight(.semibold))
                    ForEach(products) { product in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            HStack(spacing: 7) {
                                Circle().fill(productColor(product.id)).frame(width: 7, height: 7)
                                Text(product.name)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("Source: Claude Enterprise analytics · Daily buckets use UTC.")
                    .font(.caption).foregroundStyle(AnalyticsStyle.secondary)
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
                spendSkeleton
            } else {
                Text(failed ? "Enterprise spend couldn’t be loaded." : "Enterprise spend was not reported.")
                    .font(.callout).foregroundStyle(AnalyticsStyle.secondary)
                Button("Retry spend", action: retry).disabled(busy)
            }
        }
        .frame(minHeight: (hasReportedSpend || (busy && snapshot == nil)) ? 500 : nil,
               alignment: .topLeading)
        .modifier(AnalyticsCard())
    }

    /// Static placeholders reserve chart and row space without suggesting a
    /// reported zero or adding motion while the provider request is pending.
    private var spendSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailSkeletonBar(width: 116, height: 34)
            DetailSkeletonBar(width: 150, height: 12)
            DetailSkeletonBar(height: 168)
            HStack(spacing: 12) {
                DetailSkeletonBar(width: 74, height: 10)
                DetailSkeletonBar(width: 94, height: 10)
            }
            DetailSkeletonBar(width: 112, height: 12)
            ForEach(0..<4, id: \.self) { _ in
                HStack {
                    DetailSkeletonBar(width: 148, height: 13)
                    Spacer(minLength: 8)
                    DetailSkeletonBar(width: 52, height: 13)
                }
                .frame(height: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Claude spend details")
    }

    private var chartCoverageLabel: String {
        let missing = days.filter { $0.minorUnits == nil }.count
        let zeros = days.filter { $0.minorUnits == 0 }.count
        return "\(days.count) calendar days · \(missing) without reported data" +
            (zeros > 0 ? " · \(zeros) reported as zero" : "")
    }

    private func dayPopover(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ClaudeEnterpriseDateOnly.displayDate(day.id) ?? day.id)
                .font(.caption.weight(.semibold))
            ForEach(day.segments) { segment in
                HStack(spacing: 8) {
                    Circle().fill(productColor(segment.productID)).frame(width: 6, height: 6)
                    Text(segment.productName).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(Self.money(segment.minorUnits, currency: currency)).monospacedDigit()
                }
            }
            Divider()
            if let minorUnits = day.minorUnits {
                HStack {
                    Text("Total")
                    Spacer(minLength: 6)
                    Text(Self.money(minorUnits, currency: currency)).monospacedDigit()
                }
                .fontWeight(.semibold)
            } else {
                Text("No spend reported")
                    .foregroundStyle(AnalyticsStyle.secondary)
            }
        }
        .font(.caption2)
        .padding(8)
        .frame(width: 168)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        .padding(6)
        .accessibilityElement(children: .combine)
    }

    private func productColor(_ productID: String) -> Color {
        let product = products.first { $0.id == productID }
        let key = [productID, product?.name].compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        if key.contains("claude code") || key.contains("code") { return .orange }
        if key.contains("claude design") || key.contains("design") { return .green }
        if key.contains("chat and cowork") || key.contains("unified") { return .blue }
        if key.contains("cowork") { return .yellow }
        if key.contains("chat") { return .blue }
        return AnalyticsStyle.accent
    }

    private var axisDates: [Date] {
        guard let first = days.first?.date, let last = days.last?.date else { return [] }
        guard days.count > 1 else { return [first] }
        if days.count <= 7 { return [first, last] }
        return [first, days[days.count / 2].date, last]
    }

    private var chartDateLabels: some View {
        HStack(spacing: 4) {
            ForEach(Array(axisDates.enumerated()), id: \.offset) { index, date in
                if index > 0 { Spacer(minLength: 0) }
                Text(date.formatted(Date.FormatStyle(timeZone: TimeZone(secondsFromGMT: 0)!)
                    .month(.abbreviated).day()))
                    .lineLimit(1)
            }
        }
        .font(.caption2)
        .foregroundStyle(AnalyticsStyle.secondary)
        .padding(.leading, 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reporting dates, \(days.first?.id ?? "") to \(days.last?.id ?? ""), UTC")
    }

    private var utcChartCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func bucketID(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func productName(group: String?, key: String?) -> String {
        if let group = group?.trimmingCharacters(in: .whitespacesAndNewlines), !group.isEmpty {
            return group
        }
        let normalized = (key ?? "other").lowercased().replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "claude_code": return "Claude Code"
        case "chat_and_cowork_unified", "chat_and_cowork_unified_beta":
            return "Chat and Cowork unified (beta)"
        case "chat": return "Chat"
        case "cowork": return "Cowork"
        case "claude_design": return "Claude Design"
        default:
            let words = normalized.replacingOccurrences(of: "_", with: " ")
            return words.prefix(1).uppercased() + words.dropFirst()
        }
    }

    fileprivate static func money(_ minorUnits: Int, currency: String?) -> String {
        let amount = Double(minorUnits) / 100
        if let currency, currency.count == 3 {
            return amount.formatted(.currency(code: currency))
        }
        return amount.formatted(.number.precision(.fractionLength(2)))
    }

    fileprivate static func money(_ minorUnits: Double, currency: String?) -> String {
        let amount = minorUnits / 100
        if let currency, currency.count == 3 {
            return amount.formatted(.currency(code: currency).precision(.fractionLength(2...4)))
        }
        return amount.formatted(.number.precision(.fractionLength(2...4)))
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

    private var throughLabel: String? {
        let reportEnd = snapshot?.report.endDate ?? snapshot?.period.apiEndDate
        guard let reportEnd,
              let priorDay = ClaudeEnterpriseDateOnly.dayBefore(reportEnd),
              let priorDayLabel = ClaudeEnterpriseDateOnly.displayDate(priorDay)
        else { return nil }
        return priorDayLabel + " · UTC"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Skills").font(.headline)
                if let throughLabel {
                    Text("Through \(throughLabel)")
                        .font(.footnote).foregroundStyle(AnalyticsStyle.secondary)
                }
            }
            if let snapshot {
                if items.isEmpty {
                    Text("No skill invocations reported for this month.")
                        .font(.callout).foregroundStyle(AnalyticsStyle.secondary)
                } else {
                    HStack(spacing: 12) {
                        Text("Skill").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Cost / use").frame(width: 82, alignment: .trailing)
                        Text("Uses").frame(width: 48, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AnalyticsStyle.secondary)
                    ForEach(items, id: \.offset) { entry in
                        let item = entry.element
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(item.skillName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed skill")
                                .fontWeight(.semibold).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(costPerUse(item) ?? "—")
                                .monospacedDigit().frame(width: 82, alignment: .trailing)
                            Text(item.invocationCount.map { $0.formatted() } ?? "—")
                                .monospacedDigit().frame(width: 48, alignment: .trailing)
                        }
                        .padding(.vertical, 3)
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("Source: Claude Enterprise analytics · Skill activity is reported through the prior UTC day.")
                    .font(.caption).foregroundStyle(AnalyticsStyle.secondary)
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
                skillsSkeleton
            } else {
                Text(failed ? "Skill activity couldn’t be loaded." : "Skill activity was not reported.")
                    .font(.callout).foregroundStyle(AnalyticsStyle.secondary)
                Button("Retry skills", action: retry).disabled(busy)
            }
        }
        .frame(minHeight: (!items.isEmpty || (busy && snapshot == nil)) ? 310 : nil,
               alignment: .topLeading)
        .modifier(AnalyticsCard())
    }

    private var skillsSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailSkeletonBar(width: 118, height: 12)
            HStack {
                DetailSkeletonBar(width: 50, height: 11)
                Spacer(minLength: 8)
                DetailSkeletonBar(width: 70, height: 11)
                DetailSkeletonBar(width: 35, height: 11)
            }
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 10) {
                    DetailSkeletonBar(width: 160, height: 13)
                    Spacer(minLength: 8)
                    DetailSkeletonBar(width: 48, height: 13)
                    DetailSkeletonBar(width: 22, height: 13)
                }
                .frame(height: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Claude skill activity")
    }

    private func costPerUse(_ item: ClaudeEnterpriseSkillUsage) -> String? {
        guard let total = item.totalCostMinorUnits,
              let uses = item.invocationCount,
              uses > 0
        else { return nil }
        return ClaudeEnterpriseSpendView.money(Double(total) / Double(uses), currency: currency)
    }
}

private struct DetailSkeletonBar: View {
    var width: CGFloat? = nil
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: min(5, height / 3))
            .fill(Color.primary.opacity(0.11))
            .frame(width: width, height: height)
            .accessibilityHidden(true)
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
