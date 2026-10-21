import SwiftUI
import MobileAccessCore
import UIKit
import UniformTypeIdentifiers

private struct AccountCardDropDelegate: DropDelegate {
    let destination: String
    @Binding var dragging: String?
    let hover: (String, String) -> Void
    let finish: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != destination else { return }
        hover(dragging, destination)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        guard dragging != nil else { return false }
        finish()
        return true
    }
}

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
    @State private var accountOrder: [String]
    @State private var draggingAccount: String?
    private let orderStore: AccountRegistry.Store?
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(fixtureProfiles: [AccountProfile]? = nil, orderStore: AccountRegistry.Store? = nil) {
        _accounts = State(initialValue: MobileAccountCollection(fixtureProfiles: fixtureProfiles))
        _needsInitialSetup = State(initialValue: fixtureProfiles == nil && AccountRegistry.all().isEmpty)
        _accountOrder = State(initialValue: orderStore?.accountOrder() ?? AccountRegistry.accountOrder())
        self.orderStore = orderStore
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
                reloadAccountOrder()
                accounts.refreshOnOpen()
                MobileAnalytics.shared.recordDailyActiveIfNeeded()
            }
        }
        .onAppear {
            accounts.reload()
            reloadAccountOrder()
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
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(orderedProfiles, id: \.orderKey) { profile in
                                accountCard(profile, width: min(geometry.size.width, 780) - 32)
                                    .onDrag {
                                        draggingAccount = profile.orderKey
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        return NSItemProvider(object: profile.orderKey as NSString)
                                    }
                                    .onDrop(of: [UTType.plainText], delegate: AccountCardDropDelegate(
                                        destination: profile.orderKey,
                                        dragging: $draggingAccount,
                                        hover: { source, destination in
                                            reorderDuringDrag(source, onto: destination)
                                        },
                                        finish: finishDrag
                                    ))
                                    .accessibilityAction(named: "Move earlier") {
                                        moveAccount(profile.orderKey, offset: -1)
                                    }
                                    .accessibilityAction(named: "Move later") {
                                        moveAccount(profile.orderKey, offset: 1)
                                    }
                            }
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
            accounts.reload()
            reloadAccountOrder()
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

    private var orderedProfiles: [AccountProfile] {
        let visible = accounts.profiles.filter { profile in
            accounts.connected(profile.service).contains { $0.id == profile.id }
        }
        let byKey = Dictionary(uniqueKeysWithValues: visible.map { ($0.orderKey, $0) })
        let saved = accountOrder.compactMap { byKey[$0] }
        let included = Set(saved.map(\.orderKey))
        return saved + visible.filter { !included.contains($0.orderKey) }
    }

    @ViewBuilder private func accountCard(_ profile: AccountProfile, width: CGFloat) -> some View {
        let accountLabel = overviewAccountLabel(profile.label)
        if profile.service == .codex, let model = accounts.codex(profile) {
            ProviderDialCard(name: "Codex", icon: profile.service.logo, availableWidth: width,
                             reading: model.reading, connected: model.connected, busy: model.loading,
                             error: model.error, failure: model.connectionFailure,
                             accountLabel: accountLabel,
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
                             accountLabel: accountLabel,
                             onReconnect: { selected = .init(kind: .connection, profile: profile) }) {
                selected = .init(kind: .detail, profile: profile)
            }
        }
    }

    private func overviewAccountLabel(_ label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(whereSeparator: \.isWhitespace)
        if parts.count == 2,
           (parts[0].lowercased() == "account" || parts[0].lowercased() == "service"),
           !parts[1].isEmpty, parts[1].allSatisfy(\.isNumber) {
            return nil
        }
        return trimmed
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

    private func reloadAccountOrder() {
        accountOrder = orderStore?.accountOrder() ?? AccountRegistry.accountOrder()
    }

    private func persistOrder(_ keys: [String]) {
        if let orderStore { orderStore.setAccountOrder(keys) }
        else { AccountRegistry.setAccountOrder(keys) }
    }

    private func reordered(_ source: String, onto destination: String) -> [String]? {
        var keys = orderedProfiles.map(\.orderKey)
        guard source != destination,
              let from = keys.firstIndex(of: source),
              let to = keys.firstIndex(of: destination) else { return nil }
        keys.remove(at: from)
        guard let destinationIndex = keys.firstIndex(of: destination) else { return nil }
        keys.insert(source, at: destinationIndex + (from < to ? 1 : 0))
        return keys
    }

    private func reorderDuringDrag(_ source: String, onto destination: String) {
        guard let keys = reordered(source, onto: destination),
              keys != orderedProfiles.map(\.orderKey) else { return }
        if reduceMotion { accountOrder = keys }
        else { withAnimation(.snappy(duration: 0.22)) { accountOrder = keys } }
    }

    private func finishDrag() {
        let keys = orderedProfiles.map(\.orderKey)
        persistOrder(keys)
        draggingAccount = nil
        UIAccessibility.post(notification: .announcement, argument: "Account moved")
    }

    private func moveAccount(_ key: String, offset: Int) {
        var keys = orderedProfiles.map(\.orderKey)
        guard let from = keys.firstIndex(of: key), keys.indices.contains(from + offset) else { return }
        keys.swapAt(from, from + offset)
        accountOrder = keys
        persistOrder(keys)
        UIAccessibility.post(notification: .announcement,
                             argument: "Account moved \(offset < 0 ? "earlier" : "later")")
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
