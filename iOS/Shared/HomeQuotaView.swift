import SwiftUI
import WidgetKit
import MobileAccessCore

struct HomeQuotaView: View {
    // Existing review callers retain these names. Production chooses by family.
    enum Layout { case small, singleMedium, dualMedium, large, accountLarge, accountsSmall }
    let values: [ProviderReading]
    let date: Date
    let layout: Layout
    var accounts: [WidgetAccountContent]? = nil
    @Environment(\.widgetRenderingMode) private var renderingMode
    @ScaledMetric(relativeTo: .caption2) private var nameSize = 11
    @ScaledMetric(relativeTo: .caption2) private var captionSize = 10
    private var visible: [WidgetAccountContent] {
        accounts ?? values.enumerated().map { WidgetAccountContent(id: "\($0.offset)", value: $0.element) }
    }
    private var monochrome: Bool { renderingMode != .fullColor }
    private var captionInk: Color { monochrome ? .primary : WidgetPalette.reset }

    var body: some View {
        Group {
            switch layout {
            case .small:
                if let account = visible.first { tile(account, size: 100) }
            case .singleMedium:
                if let account = visible.first { accountSummary(account, size: 124, heatmap: true) }
            case .accountLarge:
                if let account = visible.first { largeAccount(account) }
            case .accountsSmall:
                VStack(spacing: 12) {
                    ForEach(Array(visible.prefix(2))) { account in
                        Link(destination: account.url) {
                            HStack(spacing: 8) {
                                dial(account, size: 56, readings: false)
                                VStack(alignment: .leading, spacing: 2) {
                                    name(account, lines: 2)
                                    status(account, compact: true)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.accessibilityLabel(account.accessibility(at: date))
                    }
                }
            case .dualMedium:
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(visible.prefix(4))) { account in
                        Link(destination: account.url) { tile(account, size: 60, readings: false).frame(maxWidth: .infinity) }
                    }
                }
            case .large:
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(Array(visible.prefix(4))) { account in
                        Link(destination: account.url) { tile(account, size: 116) }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(monochrome ? Color.primary : .white)
        .padding(layout == .small || layout == .accountsSmall ? 12 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func dial(_ account: WidgetAccountContent, size: CGFloat, readings: Bool = true) -> some View {
        AccountWidgetDial(account: account, date: date, size: size, readings: readings, compact: layout == .dualMedium || layout == .accountsSmall || layout == .large, vibrant: monochrome)
    }
    private func name(_ account: WidgetAccountContent, lines: Int = 1) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if monochrome && (account.worstPercent ?? 0) >= 85 {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).accessibilityHidden(true)
            }
            Text(account.name).font(.system(size: min(nameSize, 13), weight: .semibold)).lineLimit(lines).truncationMode(.tail)
        }
    }
    private func status(_ account: WidgetAccountContent, compact: Bool = false) -> some View {
        Text(account.status(at: date, compact: compact))
            .font(.system(size: min(captionSize, 11))).foregroundStyle(captionInk).lineLimit(2)
    }
    private func tile(_ account: WidgetAccountContent, size: CGFloat, readings: Bool = true) -> some View {
        VStack(spacing: 2) {
            dial(account, size: size, readings: readings)
            name(account).padding(.top, readings ? -6 : 2)
            status(account, compact: size <= 60)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(account.accessibility(at: date))
    }
    private func accountSummary(_ account: WidgetAccountContent, size: CGFloat, heatmap: Bool) -> some View {
        HStack(alignment: .center, spacing: 16) {
            dial(account, size: size)
            VStack(alignment: .leading, spacing: 8) {
                details(account)
                if heatmap, let history = account.tokenHistory {
                    WidgetTokenHeatmap(history: history, date: date, weeks: 27, cell: 4)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func details(_ account: WidgetAccountContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if monochrome && (account.worstPercent ?? 0) >= 85 { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)) }
                Text(account.value.service.name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
            }
            let plan = account.value.reading?.metadata?.displayPlan
            if plan != nil || !account.label.isEmpty {
                Text([plan.map { "\($0) plan" }, account.label.isEmpty ? nil : account.label].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 0) {
                if account.value.needsApp || account.value.reading == nil || account.isSaved(at: date) || (account.worstPercent ?? 0) >= 95 || account.value.reading?.metadata?.plan == "Demo" {
                    Text(account.status(at: date)).lineLimit(2)
                } else if let reading = account.value.reading {
                    ForEach(reading.windows) { window in
                        Text("\(WidgetCopy.key(window)) resets \(WidgetCopy.reset(window.resetsAt, at: date))").lineLimit(1)
                    }
                    if let budget = reading.monthlyBudget {
                        Text("Spent \(WidgetCopy.amount(budget.used, budget: budget)) of \(WidgetCopy.amount(budget.limit, budget: budget))").lineLimit(1)
                    } else if let spent = reading.metadata?.usageSpent, spent > 0 {
                        Text("Spent \(spent.formatted(.currency(code: reading.metadata?.usageCurrency ?? "USD")))").lineLimit(1)
                    }
                }
            }
            .font(.system(size: 12)).monospacedDigit().foregroundStyle(captionInk)
            .padding(.top, 4)
        }
    }
    private func largeAccount(_ account: WidgetAccountContent) -> some View {
        let splits = WidgetWeeklySplit.make(account, at: date)
        return VStack(alignment: .leading, spacing: splits.count > 1 ? 16 : 24) {
            accountSummary(account, size: splits.count > 1 ? 112 : 124, heatmap: false)
            if let history = account.tokenHistory { WidgetTokenHeatmap(history: history, date: date, weeks: 36, cell: 6.5) }
            ForEach(splits) { split in WidgetWeeklySplitView(split: split, monochrome: monochrome) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }
}

struct WidgetTokenHeatmap: View {
    let history: CodexTokenHistory
    let date: Date
    let weeks: Int
    let cell: CGFloat
    var body: some View {
        let days = Array(history.days(now: date).suffix(weeks * 7))
        let positives = days.compactMap(\.tokens).filter { $0 > 0 }.sorted()
        // The nominal grid compresses horizontally on smaller device families.
        GeometryReader { geometry in
            let side = min(cell, max(1, (geometry.size.width - CGFloat(weeks - 1) * 2) / CGFloat(weeks)))
            HStack(alignment: .top, spacing: 2) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { row in
                            let day = days[week * 7 + row]
                            RoundedRectangle(cornerRadius: 1).fill(fill(day, positives: positives)).frame(width: side, height: cell)
                        }
                    }
                }
            }
        }
        .frame(height: 7 * cell + 12)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Token activity, past \(weeks) weeks. Missing days have no record.")
    }
    private func fill(_ day: CodexTokenHistory.Day, positives: [Double]) -> Color {
        if day.isFuture { return .clear }
        guard let tokens = day.tokens else { return WidgetPalette.secondary.opacity(0.18) }
        if tokens == 0 { return Color(red: 77/255, green: 71/255, blue: 87/255) }
        let rank = Double(positives.filter { $0 <= tokens }.count) / Double(max(1, positives.count))
        return WidgetPalette.heat[rank <= 0.25 ? 0 : rank <= 0.5 ? 1 : rank <= 0.75 ? 2 : 3]
    }
}

struct WidgetWeeklySplit: Identifiable {
    struct Part { let label: String; let value: Double }
    let title: String
    let parts: [Part]
    /// Claude percentages retain their reported denominator; no renormalization.
    var denominator: Double
    var coverage: String = ""
    var id: String { title }
    static func make(_ account: WidgetAccountContent, at date: Date) -> [Self] {
        if account.value.service == .claude {
            guard let breakdown = account.value.reading?.claudeBreakdown,
                  breakdown.asOf <= date, date.timeIntervalSince(breakdown.asOf) < 7 * 86400,
                  breakdown.rows.reduce(0, { $0 + $1.percent }) <= 100 else { return [] }
            return [Self(title: "This week by product", parts: breakdown.rows.map { Part(label: $0.displayName, value: $0.percent) }, denominator: 100)]
        }
        guard let history = account.usageHistory else { return [] }
        let calendar = CodexTokenHistory.calendar
        let today = calendar.startOfDay(for: date)
        let sunday = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: date) - 1), to: today)!
        let start = CodexUsageHistory.dateString(sunday), end = CodexUsageHistory.dateString(date)
        let days = history.days.filter { $0.date >= start && $0.date <= end }
        func split(_ title: String, key: KeyPath<CodexUsageHistory.Day, [String: Double]?>) -> Self? {
            var totals: [String: Double] = [:]
            let reported = days.filter { $0.credits != nil }
            let total = reported.compactMap(\.credits).reduce(0, +)
            var hasAttribution = false
            for day in reported {
                let attribution = day[keyPath: key] ?? [:]
                if !attribution.isEmpty { hasAttribution = true }
                let attributed = attribution.values.reduce(0, +)
                // Invalid or overlapping attribution cannot be represented as a split.
                guard attributed <= (day.credits ?? 0) + 0.000001 else { return nil }
                for (key, value) in attribution { totals[key, default: 0] += value }
                let unknown = max(0, (day.credits ?? 0) - attributed)
                if unknown > 0.000001 { totals["Unattributed", default: 0] += unknown }
            }
            guard hasAttribution, total > 0 else { return nil }
            let sorted = totals.filter { $0.value > 0 && $0.value.isFinite }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            guard !sorted.isEmpty else { return nil }
            var parts = sorted.prefix(2).map { Part(label: $0.key, value: $0.value) }
            let rest = sorted.dropFirst(2)
            if rest.count == 1, let last = rest.first { parts.append(Part(label: last.key, value: last.value)) }
            else if !rest.isEmpty { parts.append(Part(label: "Other", value: rest.reduce(0) { $0 + $1.value })) }
            let elapsedDays = (calendar.dateComponents([.day], from: sunday, to: today).day ?? 0) + 1
            let coverage = reported.count < elapsedDays ? "\(reported.count)/\(elapsedDays) days" : ""
            return Self(title: title, parts: parts, denominator: total, coverage: coverage)
        }
        return [split("This week by app", key: \.surfaces), split("This week by model", key: \.models)].compactMap { $0 }
    }
}

struct WidgetWeeklySplitView: View {
    let split: WidgetWeeklySplit
    let monochrome: Bool
    private func color(_ index: Int) -> Color { monochrome ? Color.primary.opacity(1 - Double(index) * 0.25) : WidgetPalette.heat[3 - min(index, 2)] }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(split.title).font(.system(size: 12, weight: .semibold))
                if !split.coverage.isEmpty {
                    Spacer(minLength: 4)
                    Text(split.coverage).font(.system(size: 9)).foregroundStyle(monochrome ? Color.primary.opacity(0.6) : WidgetPalette.secondary)
                }
            }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(Array(split.parts.enumerated()), id: \.offset) { index, part in
                        RoundedRectangle(cornerRadius: 1).fill(color(index))
                            .frame(width: max(0, geometry.size.width - CGFloat(split.parts.count - 1) * 2) * part.value / max(1, split.denominator))
                    }
                }
            }.frame(height: 8).widgetAccentable()
            HStack(spacing: 8) {
                ForEach(Array(split.parts.enumerated()), id: \.offset) { index, part in
                    HStack(spacing: 3) {
                        Rectangle().fill(color(index)).frame(width: 6, height: 6)
                        Text("\(part.label) \(Int((part.value / max(1, split.denominator) * 100).rounded()))%").lineLimit(1)
                    }
                }
            }.font(.system(size: 10))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(split.title + (split.coverage.isEmpty ? "" : ", \(split.coverage) reported") + ": " + split.parts.map { "\($0.label), \(Int(($0.value / max(1, split.denominator) * 100).rounded())) percent" }.joined(separator: ", "))
    }
}

/// A flat plum surface; WidgetKit owns the outer shape and rendering treatment.
/// Keep it inside the removable container background for tinted/clear modes.
struct HomeWidgetBackground: View {
    var body: some View {
        Color(red: 30/255, green: 18/255, blue: 35/255)
    }
}
