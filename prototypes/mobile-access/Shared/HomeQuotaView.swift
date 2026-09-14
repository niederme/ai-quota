import SwiftUI
import MobileAccessCore

/// Mirrors the four Mac widget layouts; all values remain timestamped provider readings.
struct HomeQuotaView: View {
    enum Layout { case small, singleMedium, dualMedium, large }
    let values: [ProviderReading]
    let date: Date
    let layout: Layout
    private let accent = Color(red: 0.62, green: 0.22, blue: 0.93)

    var body: some View {
        Group {
            switch layout {
            case .small:
                if let value = values.first { gauge(value, size: 90) }
            case .singleMedium:
                if let value = values.first {
                    HStack(alignment: .top, spacing: 14) {
                        gauge(value, size: 90).frame(width: 120)
                        Divider()
                        details(value).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            case .dualMedium:
                let visible = enrolledValues
                HStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.service) { index, value in
                        if index > 0 { Divider().padding(.vertical, 8) }
                        Link(destination: value.service.url) {
                            gauge(value, size: visible.count == 1 ? 90 : 80)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            case .large:
                VStack(spacing: 10) {
                    HStack {
                        Text("AIQuota").font(.subheadline.bold())
                        Spacer()
                        Text("● 5h").foregroundStyle(accent)
                        Text("● 7d").foregroundStyle(accent.opacity(0.5))
                    }.font(.caption.bold())
                    Divider()
                    HStack(spacing: 0) {
                        ForEach(Array(values.enumerated()), id: \.element.service) { index, value in
                            if index > 0 { Divider() }
                            Link(destination: value.service.url) { gauge(value, size: 96).frame(maxWidth: .infinity) }
                        }
                    }.frame(maxHeight: .infinity)
                    Divider()
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(values.enumerated()), id: \.element.service) { index, value in
                            if index > 0 { Divider() }
                            Link(destination: value.service.url) { details(value).frame(maxWidth: .infinity, alignment: .leading) }
                        }
                    }.frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }.buttonStyle(.plain).foregroundStyle(.primary).padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // A failed enrolled service stays visible. Only truly empty slots may collapse.
    private var enrolledValues: [ProviderReading] {
        let enrolled = values.filter { $0.reading != nil || $0.needsApp }
        return enrolled.count == 1 ? enrolled : values
    }
    private func name(_ value: ProviderReading) -> String { value.service == .claude ? "Claude Code" : "Codex" }
    private func stale(_ value: ProviderReading) -> Bool { value.needsApp || WidgetFreshness.isOld(value.reading, at: date) }
    private func tint(_ value: ProviderReading) -> Color {
        guard !stale(value) else { return .secondary }
        let used = max(value.reading?.shortTerm?.usedPercent ?? 0, value.reading?.weekly?.usedPercent ?? 0)
        return used >= 95 ? .red : used >= 85 ? Color(red: 1, green: 0.65, blue: 0) : accent
    }
    private func gauge(_ value: ProviderReading, size: CGFloat) -> some View {
        VStack(spacing: 3) {
            ZStack {
                ring(value.reading?.shortTerm, width: size * 0.09, color: tint(value))
                ring(value.reading?.weekly, width: size * 0.07, color: tint(value).opacity(0.5)).padding(size * 0.1)
                VStack(spacing: 1) {
                    if value.needsApp {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: size * 0.16))
                    } else {
                        Image(value.service.logo).resizable().scaledToFit().frame(width: size * 0.16, height: size * 0.16)
                    }
                    Text(percent(value.reading?.shortTerm) + " 5h").font(.system(size: size * 0.175, weight: .bold))
                    Text(percent(value.reading?.weekly) + " 7d").font(.system(size: size * 0.125, weight: .semibold)).opacity(0.5)
                }.foregroundStyle(tint(value)).monospacedDigit()
            }.frame(width: size, height: size)
                .padding(.bottom, -size * 0.08)
            Text(name(value)).font(.system(size: 12, weight: .bold)).lineLimit(1)
            if value.needsApp {
                Text("Reconnect in app").foregroundStyle(.secondary)
            } else if value.reading == nil {
                Text("Sign in to AIQuota").foregroundStyle(.secondary)
            } else if stale(value) {
                Text("Saved reading").foregroundStyle(.secondary)
            } else {
                reset(value.reading?.shortTerm, label: "5h")
                if layout != .singleMedium && layout != .large && (value.reading?.weekly?.usedPercent ?? 0) >= 85 {
                    reset(value.reading?.weekly, label: "7d")
                }
            }
        }.font(.system(size: 11)).multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
    }
    private func ring(_ window: QuotaWindow?, width: CGFloat, color: Color) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75).stroke(.secondary.opacity(0.22), style: StrokeStyle(lineWidth: width, dash: window == nil ? [2, 3] : []))
            if let window {
                Circle().trim(from: 0, to: 0.75 * window.usedPercent / 100).stroke(color, lineWidth: width)
            }
        }.rotationEffect(.degrees(135))
    }
    private func percent(_ window: QuotaWindow?) -> String { window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "—" }
    private func reset(_ window: QuotaWindow?, label: String) -> some View {
        Group {
            if let end = window?.resetsAt, end > date {
                Text("\(label) resets \(end.formatted(.dateTime.hour().minute()))")
            } else { Text("\(label) reset unavailable") }
        }.foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
    }
    private func details(_ value: ProviderReading) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let reading = value.reading {
                if let window = value.service == .codex ? reading.weekly : reading.shortTerm { row("Remaining", "\(Int((100 - window.usedPercent).rounded()))%", icon: "sparkles") }
                if let plan = reading.metadata?.plan { row("Plan", plan.capitalized, icon: "person.fill") }
                if let balance = reading.metadata?.balanceUSD { row("Balance", balance.formatted(.currency(code: "USD")), icon: "creditcard.fill") }
                if let spent = reading.metadata?.usageSpent {
                    let amount = reading.metadata?.usageCurrency.map { spent.formatted(.currency(code: $0)) } ?? spent.formatted()
                    row(value.service == .codex ? "Spent" : "Credits used", amount, icon: "plus.circle.fill", color: .orange)
                }
                if value.needsApp { Text("Connection needs attention").foregroundStyle(.secondary) }
                else if stale(value) { Text("Saved reading").foregroundStyle(.secondary) }
                else { reset(reading.weekly, label: "7d") }
            } else {
                Text(value.needsApp ? "Reconnect in AIQuota" : "Sign in to AIQuota").fontWeight(.semibold)
                Text("Connect \(name(value)) in the app.").foregroundStyle(.secondary)
            }
        }.font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
    }
    private func row(_ label: String, _ value: String, icon: String, color: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: icon).frame(width: 12).foregroundStyle(.secondary)
            Text(label + ":").foregroundStyle(.secondary)
            Text(value).bold().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

/// Keep this inside WidgetKit's removable container background so tinted and
/// clear appearances continue to receive the system's own glass treatment.
struct HomeWidgetBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(uiColor: .systemGroupedBackground)
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }
}
