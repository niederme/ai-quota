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
            Group {
                if needsApp { Image(systemName: "exclamationmark").font(.system(size: 9, weight: .bold)) }
                else { Circle().fill(.primary).frame(width: 3, height: 3) }
            }
        }.padding(2.52)
    }
    private func ring(_ window: QuotaWindow?, width: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(.primary.opacity(0.18), style: StrokeStyle(lineWidth: width, dash: window == nil ? [1, 2] : []))
            if let window {
                Circle().trim(from: 0, to: 0.75 * min(1, max(0, window.usedPercent / 100)))
                    .stroke(.primary.opacity(opacity), style: StrokeStyle(lineWidth: width, dash: []))
            }
        }.rotationEffect(.degrees(135))
    }
    private func spoken(_ window: QuotaWindow?) -> String {
        window.map { "\(Int($0.usedPercent.rounded())) percent" } ?? "Unavailable"
    }
}

struct ProviderReading: Sendable {
    let service: QuotaService
    let reading: QuotaReading?
    let needsApp: Bool
}

struct CodexDial: View {
    let value: ProviderReading
    let date: Date
    var logoScale: CGFloat = 1
    private var stale: Bool { WidgetFreshness.isOld(value.reading, at: date) || value.needsApp }
    private var warning: Bool { WidgetFreshness.limitReached(value.reading) }
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                ring(value.reading?.shortTerm, width: size * 0.12, opacity: 1)
                    .padding(size * 0.09)
                ring(value.reading?.weekly, width: size * 0.12, opacity: 0.6)
                    .padding(size * 0.21 + 1)
                if value.needsApp {
                    Image(systemName: "exclamationmark").font(.system(size: size * 0.3, weight: .bold))
                } else {
                Image(value.service.logo)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.324 * logoScale, height: size * 0.324 * logoScale)
                    .foregroundStyle(.primary)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value.service.name) allowance used")
        .accessibilityValue("Five hours: \(formatted(value.reading?.shortTerm)). Seven days: \(formatted(value.reading?.weekly)). \(stale ? "Reading needs refreshing." : "") \(warning ? "An allowance limit is reached." : "")")
        .accessibilityHint("Opens AI Quota")
    }
    private func formatted(_ window: QuotaWindow?) -> String {
        window.map { "\(Int($0.usedPercent.rounded())) percent" } ?? "Unavailable"
    }
    private func ring(_ window: QuotaWindow?, width: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(.primary.opacity(0.18), style: StrokeStyle(lineWidth: width, dash: window == nil ? [2, 3] : []))
            if let window {
                Circle().trim(from: 0, to: 0.75 * min(1, max(0, window.usedPercent / 100)))
                    .stroke(.primary.opacity(opacity),
                            style: StrokeStyle(lineWidth: width, dash: []))
            }
        }.rotationEffect(.degrees(135))
    }
}


struct ServiceDetailsView: View {
    let value: ProviderReading
    let date: Date
    var body: some View {
                HStack(spacing: 5) {
                    CodexDial(value: value, date: date, logoScale: 0.8).frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(value.service.name).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        metric(value.reading?.shortTerm, label: "5h").foregroundStyle(.primary)
                        metric(value.reading?.weekly, label: "7d").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }

    }
    private func metric(_ window: QuotaWindow?, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "—")
                .font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 10))
        }.lineLimit(1).minimumScaleFactor(0.8)
    }
}
