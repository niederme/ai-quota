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
                Text(reading?.metadata?.plan == "Demo" ? "Demo" : service.name).font(.system(size: compact ? 11 : 13, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            VStack(alignment: .leading, spacing: 0) {
                percentage(reading?.primaryWindow, label: reading?.primaryWindow?.compactLabel ?? "")
                    .foregroundStyle(.primary)
                if let secondary = reading?.secondaryWindow {
                    percentage(secondary, label: secondary.compactLabel).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(service.name) \(reading?.metadata?.plan == "Demo" ? "sample" : "allowance") used")
        .accessibilityValue("\(reading?.accessibilitySummary ?? "Allowance unavailable"). \(stale ? "Reading needs refreshing." : "")")
        .accessibilityHint("Opens AI Quota")
    }
    private func percentage(_ window: QuotaWindow?, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "N/A")
                .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 10, weight: .regular))
        }.lineLimit(1).minimumScaleFactor(0.75)
    }
    private var miniGauge: some View {
        ZStack {
            ring(reading?.primaryWindow, width: reading?.windows.count == 1 ? 4.2 : 3.36, opacity: 1)
                .padding(reading?.windows.count == 1 ? 0.42 : 0)
            if let secondary = reading?.secondaryWindow {
                ring(secondary, width: 3.36, opacity: 0.6).padding(4.36)
            }
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
                ring(value.reading?.primaryWindow, width: value.reading?.windows.count == 1 ? size * 0.13 : size * 0.12, opacity: 1)
                    .padding(value.reading?.windows.count == 1 ? size * 0.095 : size * 0.09)
                if let secondary = value.reading?.secondaryWindow {
                    ring(secondary, width: size * 0.12, opacity: 0.6)
                        .padding(size * 0.21 + 1)
                }
                if value.reading?.metadata?.plan == "Demo" {
                    Text("Demo").font(.system(size: size * 0.16, weight: .semibold))
                } else if value.needsApp {
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
        .accessibilityLabel("\(value.service.name) \(value.reading?.metadata?.plan == "Demo" ? "sample" : "allowance") used")
        .accessibilityValue("\(value.reading?.accessibilitySummary ?? "Allowance unavailable"). \(stale ? "Reading needs refreshing." : "") \(warning ? "An allowance limit is reached." : "")")
        .accessibilityHint("Opens AI Quota")
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
                        Text(value.service.name).font(.system(size: 16, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        metric(value.reading?.primaryWindow, label: value.reading?.primaryWindow?.compactLabel ?? "").foregroundStyle(.primary)
                        if let secondary = value.reading?.secondaryWindow {
                            metric(secondary, label: secondary.compactLabel).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }

    }
    private func metric(_ window: QuotaWindow?, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "N/A")
                .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 16, weight: .regular))
        }.lineLimit(1).minimumScaleFactor(0.8)
    }
}
