import SwiftUI
import MobileAccessCore

struct ProviderReading: Sendable {
    let service: QuotaService
    let reading: QuotaReading?
    let needsApp: Bool
    var updateFailed = false
}

struct AccountLockView: View {
    let account: WidgetAccountContent
    let date: Date
    var circular = false
    var showAccountNames = false
    var body: some View {
        Group {
            if circular {
                GeometryReader { geometry in
                    let size = min(geometry.size.width, geometry.size.height)
                    AccountWidgetDial(account: account, date: date, size: size, readings: false, vibrant: true, curvedCaption: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HStack(spacing: 2) {
                    TunedLockScreenDial(account: account, date: date).frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(account.compactName(showAccountNames: showAccountNames))
                            .font(.system(size: 14, weight: .regular)).lineLimit(1)
                        if account.value.needsApp || account.value.reading == nil || account.isSaved(at: date) {
                            Text(account.status(at: date)).lineLimit(2).opacity(0.6)
                        } else {
                            let reading = account.value.reading
                            Text(WidgetCopy.metric(reading?.primaryDisplayWindow)).lineLimit(1)
                            if let secondary = reading?.secondaryWindow {
                                Text(WidgetCopy.metric(secondary)).lineLimit(1).opacity(0.6)
                            } else {
                                if let reset = LockScreenResetPresentation.make(reading: reading, needsApp: false, at: date) {
                                    Text(reset.text).lineLimit(1).opacity(0.6)
                                }
                            }
                        }
                    }
                    .font(.system(size: 14, weight: .medium)).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(account.accessibility(at: date))
        .accessibilityHint("Opens AIQuota")
    }
}

/// The tuned Weather-adjacent rectangular accessory dial. Keep its inset,
/// stroke and logo proportions independent of Home Screen/circular dials.
private struct TunedLockScreenDial: View {
    private final class ResourceAnchor: NSObject {}
    let account: WidgetAccountContent
    let date: Date
    private var reading: QuotaReading? { account.value.reading }
    private var single: Bool { reading?.windows.count == 1 || reading?.budgetOnly != nil }
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                ring(reading?.primaryDisplayWindow, width: size * (single ? 0.13 : 0.12), opacity: 1)
                    .padding(size * (single ? 0.095 : 0.09))
                if let secondary = reading?.secondaryWindow {
                    ring(secondary, width: size * 0.12, opacity: 0.6).padding(size * 0.21 + 1)
                }
                if account.value.needsApp {
                    Image(systemName: "exclamationmark").font(.system(size: size * 0.3, weight: .bold))
                } else if reading?.metadata?.plan == "Demo" {
                    Text("Demo").font(.system(size: size * 0.16, weight: .semibold))
                } else {
                    Image(account.value.service.logo, bundle: Bundle(for: ResourceAnchor.self)).renderingMode(.template).resizable().scaledToFit()
                        .frame(width: size * 0.324 * 0.8, height: size * 0.324 * 0.8)
                }
            }
            .frame(width: size, height: size).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(3)
        .opacity(account.isSaved(at: date) ? 0.45 : 1)
        .overlay(alignment: .bottomTrailing) {
            if account.isSaved(at: date) && !account.value.needsApp {
                Image(systemName: "clock.fill").font(.system(size: 11)).accessibilityHidden(true)
            }
        }
    }
    private func ring(_ window: QuotaWindow?, width: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(.primary.opacity(0.18), style: StrokeStyle(lineWidth: width, dash: window == nil ? [2, 3] : []))
            if let window {
                Circle().trim(from: 0, to: 0.75 * min(1, max(0, window.usedPercent / 100)))
                    .stroke(.primary.opacity(opacity), style: StrokeStyle(lineWidth: width))
            }
        }.rotationEffect(.degrees(135))
    }
}

struct AccountsLockView: View {
    let accounts: [WidgetAccountContent]
    let date: Date
    var showAccountNames = false
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(accounts.prefix(2))) { account in
                Link(destination: account.url) {
                    VStack(spacing: 0) {
                        AccountWidgetDial(account: account, date: date, size: 56, readings: false, compact: true, vibrant: true)
                        HStack(spacing: 2) {
                            if (account.worstPercent ?? 0) >= 85 { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8)) }
                            Text(account.compactName(showAccountNames: showAccountNames)).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(account.accessibility(at: date))
            }
        }.buttonStyle(.plain)
    }
}

// Compatibility entry points for app previews and existing review fixtures.
struct CodexDial: View {
    let value: ProviderReading
    let date: Date
    var logoScale: CGFloat = 1
    var body: some View { AccountLockView(account: .init(id: value.service.rawValue, value: value), date: date, circular: true) }
}
struct ServiceDetailsView: View {
    let value: ProviderReading
    let date: Date
    var body: some View { AccountLockView(account: .init(id: value.service.rawValue, value: value), date: date) }
}
struct CompactQuotaView: View {
    let service: QuotaService
    let reading: QuotaReading?
    let needsApp: Bool
    let date: Date
    var compact = false
    var updateFailed = false
    var body: some View {
        let account = WidgetAccountContent(id: service.rawValue, value: .init(service: service, reading: reading, needsApp: needsApp, updateFailed: updateFailed))
        if compact { AccountsLockView(accounts: [account], date: date) }
        else { AccountLockView(account: account, date: date) }
    }
}
