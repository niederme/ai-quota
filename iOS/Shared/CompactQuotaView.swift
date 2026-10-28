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
    var body: some View {
        Group {
            if circular {
                GeometryReader { geometry in
                    let size = min(geometry.size.width, geometry.size.height)
                    AccountWidgetDial(account: account, date: date, size: size, readings: false, vibrant: true, curvedCaption: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HStack(spacing: 4) {
                    AccountWidgetDial(account: account, date: date, size: 60, readings: false, vibrant: true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(account.name).fontWeight(.semibold).lineLimit(1)
                        if account.value.needsApp || account.value.reading == nil || account.isSaved(at: date) {
                            Text(account.status(at: date)).lineLimit(2).opacity(0.6)
                        } else {
                            let reading = account.value.reading
                            Text(WidgetCopy.metric(reading?.primaryDisplayWindow)).lineLimit(1)
                            if let secondary = reading?.secondaryWindow {
                                Text(WidgetCopy.metric(secondary)).lineLimit(1).opacity(0.6)
                            } else {
                                Text(WidgetCopy.reset(reading?.primaryDisplayWindow?.resetsAt, at: date)).lineLimit(1).opacity(0.6)
                            }
                        }
                    }
                    .font(.system(size: 14, weight: .medium)).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading).offset(y: -5)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(account.accessibility(at: date))
        .accessibilityHint("Opens AIQuota")
    }
}

struct AccountsLockView: View {
    let accounts: [WidgetAccountContent]
    let date: Date
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(accounts.prefix(2))) { account in
                Link(destination: account.url) {
                    VStack(spacing: 0) {
                        AccountWidgetDial(account: account, date: date, size: 56, readings: false, compact: true, vibrant: true)
                        HStack(spacing: 2) {
                            if (account.worstPercent ?? 0) >= 85 { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8)) }
                            Text(account.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
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
