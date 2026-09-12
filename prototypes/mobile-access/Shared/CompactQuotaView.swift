import SwiftUI
import MobileAccessCore

/// Weather-inspired hierarchy for the alternate rectangular Lock Screen layout.
struct CompactQuotaView: View {
    let service: QuotaService
    let reading: QuotaReading?
    let needsApp: Bool
    let date: Date
    var compact = false
    private var stale: Bool { needsApp || WidgetFreshness.isOld(reading, at: date) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                miniGauge.frame(width: 28, height: 28)
                Text(service.name).font(.system(size: compact ? 11 : 13, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
                if stale { Image(systemName: "clock").font(.system(size: 9)) }
            }
            VStack(alignment: .leading, spacing: 0) {
                percentage(reading?.shortTerm, label: "5h")
                    .foregroundStyle(.primary)
                percentage(reading?.weekly, label: "7d")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(service.name) allowance used")
        .accessibilityValue("Five hours: \(spoken(reading?.shortTerm)). Seven days: \(spoken(reading?.weekly)). \(stale ? "Reading needs refreshing." : "")")
        .accessibilityHint("Opens AI Quota")
    }
    private func percentage(_ window: QuotaWindow?, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "—")
                .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 10, weight: .regular))
        }.lineLimit(1).minimumScaleFactor(0.75)
    }
    private var miniGauge: some View {
        ZStack {
            ring(reading?.shortTerm, width: 3.36, opacity: 1)
            ring(reading?.weekly, width: 3.36, opacity: 0.6).padding(4.36)
            Circle().fill(.primary).frame(width: 3, height: 3)
        }.padding(2.52)
    }
    private func ring(_ window: QuotaWindow?, width: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(.primary.opacity(0.18), style: StrokeStyle(lineWidth: width, dash: window == nil ? [1, 2] : []))
            if let window {
                Circle().trim(from: 0, to: 0.75 * min(1, max(0, window.usedPercent / 100)))
                    .stroke(.primary.opacity(opacity * (stale ? 0.45 : 1)), style: StrokeStyle(lineWidth: width, dash: stale ? [1, 1] : []))
            }
        }.rotationEffect(.degrees(135))
    }
    private func spoken(_ window: QuotaWindow?) -> String {
        window.map { "\(Int($0.usedPercent.rounded())) percent" } ?? "Unavailable"
    }
}
