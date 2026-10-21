import SwiftUI
import MobileAccessCore
import UIKit

private struct AccountSheetSelection: Identifiable {
    enum Kind { case detail, connection, settings }
    let kind: Kind
    var profile: AccountProfile? = nil
    var id: String { "\(kind)-\(profile?.service.rawValue ?? "")-\(profile?.id ?? "")" }
}

struct MultiAccountOverviewView: View {
    @State private var accounts: MobileAccountCollection
    @State private var onboarding = OnboardingProgress()
    @State private var needsInitialSetup: Bool
    @State private var selected: AccountSheetSelection?
    @State private var pendingProfile: AccountProfile?
    @State private var serviceOrder = AccountRegistry.serviceOrder()
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 0
    @Environment(\.scenePhase) private var scenePhase

    init(fixtureProfiles: [AccountProfile]? = nil) {
        _accounts = State(initialValue: MobileAccountCollection(fixtureProfiles: fixtureProfiles))
        _needsInitialSetup = State(initialValue: fixtureProfiles == nil && AccountRegistry.all().isEmpty)
    }

    var body: some View {
        Group {
            if needsInitialSetup {
                OnboardingView(codex: accounts.setupCodex, claude: accounts.setupClaude,
                               progress: onboarding, accounts: accounts, allowsDeferral: false,
                               onFinish: {
                                   accounts.reload()
                                   needsInitialSetup = !accounts.hasConnection
                               })
                    .onAppear { onboarding.resumeRequiredSetup(hasConnectedService: accounts.hasConnection) }
            } else {
                dashboard
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { MobileBackgroundRefresh.shared.scheduleNext() }
            if phase == .active {
                accounts.reload()
                accounts.refreshOnOpen()
                MobileAnalytics.shared.recordDailyActiveIfNeeded()
            }
        }
        .onAppear {
            accounts.reload()
            if !accounts.hasConnection { needsInitialSetup = true }
            MobileAnalytics.shared.observeServices(codex: !accounts.connected(.codex).isEmpty,
                                                   claude: !accounts.connected(.claude).isEmpty,
                                                   isDemo: false)
            MobileAnalytics.shared.recordLaunchIfNeeded()
        }
    }

    private var dashboard: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(serviceOrder, id: \.self) { service in
                            serviceSection(service, width: min(geometry.size.width, 780) - 32)
                        }
                        freshness.frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await accounts.refreshAll() }
                .background { OverviewBackground().ignoresSafeArea() }
            }
            .navigationTitle("AIQuota")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        MobileAnalytics.shared.manualRefresh()
                        Task { await accounts.refreshAll() }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .tint(OverviewStyle.primary)
                        .accessibilityLabel("Refresh usage")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { selected = .init(kind: .settings) } label: { Image(systemName: "gearshape") }
                        .tint(OverviewStyle.primary)
                        .accessibilityLabel("Settings")
                }
            }
            .onOpenURL { url in
                guard url.scheme == "aiquota-probe" else { return }
                accounts.reload()
                if url.host == "overview" { accounts.refreshOnOpen(); return }
                guard let service = QuotaService(rawValue: url.host ?? "") else { return }
                let requestedID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "account" })?.value
                let profile = accounts.connected(service).first(where: { $0.id == requestedID })
                    ?? AccountRegistry.defaultProfile(for: service)
                if let profile { selected = .init(kind: .detail, profile: profile) }
            }
            .task(id: "\(scenePhase)-\(refreshMinutes)") {
                guard scenePhase == .active else { return }
                accounts.refreshOnOpen()
                while !Task.isCancelled {
                    let percentages = accounts.profiles.flatMap { profile -> [Double] in
                        let reading = profile.service == .codex ? accounts.codex(profile)?.reading : accounts.claude(profile)?.reading
                        return (reading?.windows.compactMap(\.usedPercent) ?? []) +
                            (reading?.monthlyBudget.map { [$0.usedPercent] } ?? [])
                    }
                    let minutes = refreshMinutes == 0 ? (percentages.contains { $0 >= 85 } ? 1 : 5) : max(1, refreshMinutes)
                    do { try await Task.sleep(for: .seconds(minutes * 60)) }
                    catch { return }
                    await accounts.refreshAll()
                }
            }
        }
        .tint(OverviewStyle.accent)
        .sheet(item: $selected, onDismiss: {
            if let pendingProfile { accounts.discardIfUnconnected(pendingProfile) }
            pendingProfile = nil
            accounts.reload()
            if !accounts.hasConnection {
                onboarding.replay()
                needsInitialSetup = true
            }
        }) { selection in
            ServiceAccountSheet {
                sheetContent(selection)
            }
        }
    }

    @ViewBuilder private func serviceSection(_ service: QuotaService, width: CGFloat) -> some View {
        let profiles = accounts.connected(service)
        if !profiles.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(service.logo).resizable().scaledToFit().frame(width: 18, height: 18)
                        Text(service.name).font(.headline)
                        Text("\(profiles.count)").font(.caption.weight(.semibold))
                            .foregroundStyle(OverviewStyle.secondary)
                    }
                    .contentShape(Rectangle())
                    .draggable(service.rawValue)
                    .dropDestination(for: String.self) { items, _ in
                        guard let source = items.first.flatMap(QuotaService.init(rawValue:)) else { return false }
                        move(source, before: service)
                        return true
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(service.name), \(profiles.count) \(profiles.count == 1 ? "account" : "accounts")")
                    .accessibilityAction(named: "Move earlier") { move(service, offset: -1) }
                    .accessibilityAction(named: "Move later") { move(service, offset: 1) }
                    .contextMenu {
                        Button("Move earlier", systemImage: "arrow.up") { move(service, offset: -1) }
                            .disabled(serviceOrder.first == service)
                        Button("Move later", systemImage: "arrow.down") { move(service, offset: 1) }
                            .disabled(serviceOrder.last == service)
                    }
                    Spacer()
                    Button("Add account", systemImage: "plus") { add(service) }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Add \(service.name) account")
                }
                .foregroundStyle(OverviewStyle.primary)
                ForEach(profiles, id: \.id) { profile in
                    accountCard(profile, width: width)
                }
            }
        }
    }

    @ViewBuilder private func accountCard(_ profile: AccountProfile, width: CGFloat) -> some View {
        let showLabel = accounts.connected(profile.service).count > 1 || profile.label != "Account 1"
        if profile.service == .codex, let model = accounts.codex(profile) {
            ProviderDialCard(name: "Codex", icon: profile.service.logo, availableWidth: width,
                             reading: model.reading, connected: model.connected, busy: model.loading,
                             error: model.error, failure: model.connectionFailure,
                             accountLabel: showLabel ? profile.label : nil,
                             history: model.history, historyUnavailable: model.historyUnavailable,
                             tokenHistory: model.tokenHistory, tokenHistoryUnavailable: model.tokenHistoryUnavailable,
                             tokenHistoryLoading: model.tokenHistoryLoading,
                             onReconnect: { selected = .init(kind: .connection, profile: profile) }) {
                selected = .init(kind: .detail, profile: profile)
            }
        } else if let model = accounts.claude(profile) {
            ProviderDialCard(name: "Claude", icon: profile.service.logo, availableWidth: width,
                             reading: model.reading, connected: model.connected, busy: model.loading,
                             error: model.error, failure: model.connectionFailure,
                             accountLabel: showLabel ? profile.label : nil,
                             onReconnect: { selected = .init(kind: .connection, profile: profile) }) {
                selected = .init(kind: .detail, profile: profile)
            }
        }
    }

    @ViewBuilder private func sheetContent(_ selection: AccountSheetSelection) -> some View {
        switch selection.kind {
        case .settings:
            MultiAccountSettingsView(accounts: accounts, onboarding: onboarding)
        case .connection:
            if let profile = selection.profile {
                if profile.service == .codex, let model = accounts.codex(profile) {
                    ProbeView(model: model)
                } else if let model = accounts.claude(profile) {
                    ClaudeProbeView(model: model)
                }
            }
        case .detail:
            if let profile = selection.profile {
                if profile.service == .codex, let model = accounts.codex(profile) {
                    ServiceDetailContent(name: "Codex", icon: profile.service.logo,
                                         reading: model.reading, connected: model.connected, busy: model.busy,
                                         error: model.error, failure: model.connectionFailure,
                                         accountLabel: profile.label, history: model.history,
                                         historyUnavailable: model.historyUnavailable,
                                         refresh: { model.refresh() }) { ProbeView(model: model) }
                } else if let model = accounts.claude(profile) {
                    ServiceDetailContent(name: "Claude", icon: profile.service.logo,
                                         reading: model.reading, connected: model.connected, busy: model.busy,
                                         error: model.error, failure: model.connectionFailure,
                                         accountLabel: profile.label, claudeAccount: model,
                                         refresh: { model.refresh() }) { ClaudeProbeView(model: model) }
                }
            }
        }
    }

    private func add(_ service: QuotaService) {
        let profile = accounts.add(service)
        pendingProfile = profile
        selected = .init(kind: .connection, profile: profile)
    }

    private func move(_ service: QuotaService, offset: Int) {
        guard let from = serviceOrder.firstIndex(of: service),
              serviceOrder.indices.contains(from + offset) else { return }
        serviceOrder.swapAt(from, from + offset)
        AccountRegistry.setServiceOrder(serviceOrder)
        UIAccessibility.post(notification: .announcement, argument: "\(service.name) moved \(offset < 0 ? "earlier" : "later")")
    }

    private func move(_ source: QuotaService, before destination: QuotaService) {
        guard source != destination, let from = serviceOrder.firstIndex(of: source),
              let to = serviceOrder.firstIndex(of: destination) else { return }
        serviceOrder.remove(at: from)
        serviceOrder.insert(source, at: to)
        AccountRegistry.setServiceOrder(serviceOrder)
        UIAccessibility.post(notification: .announcement, argument: "\(source.name) moved")
    }

    private var freshness: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let readings = accounts.profiles.compactMap { profile -> Date? in
                profile.service == .codex ? accounts.codex(profile)?.reading?.fetchedAt : accounts.claude(profile)?.reading?.fetchedAt
            }
            if let oldest = readings.min() {
                Text(overviewFreshnessLabel(oldest, at: context.date, saved: false)
                    .replacingOccurrences(of: "Updated", with: "Refreshed"))
                    .font(.footnote).foregroundStyle(OverviewStyle.secondary)
            }
        }
    }
}
