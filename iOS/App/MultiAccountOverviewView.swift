import SwiftUI
import MobileAccessCore
import UIKit
import UniformTypeIdentifiers
import WidgetKit

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
    @State private var quotaInsights = MobileQuotaInsightModel()
    @State private var resetNotice: CodexResetNotice
    @State private var showResetDetails = false
    @AppStorage(CodexResetNotice.dismissalKey) private var dismissedResetID = ""
    private let orderStore: AccountRegistry.Store?
    private let isFixtureMode: Bool
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(fixtureProfiles: [AccountProfile]? = nil, orderStore: AccountRegistry.Store? = nil,
         resetNotice: CodexResetNotice? = nil) {
        _accounts = State(initialValue: MobileAccountCollection(fixtureProfiles: fixtureProfiles))
        _resetNotice = State(initialValue: resetNotice ?? CodexResetNotice())
        _needsInitialSetup = State(initialValue: fixtureProfiles == nil && AccountRegistry.all().isEmpty)
        _accountOrder = State(initialValue: orderStore?.accountOrder() ?? AccountRegistry.accountOrder())
        self.orderStore = orderStore
        isFixtureMode = fixtureProfiles != nil
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
                let wide = min(geometry.size.width, 720) - 32 >= 600 && !typeSize.isAccessibilitySize
                OverviewScrollView {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let queries = MobileQuotaInsightModel.queries(accounts)
                        VStack(alignment: .leading, spacing: 8) {
                            let insight = quotaInsights.current(queries: queries, now: context.date)
                            OverviewAlerts(announcement: resetAnnouncement, forecast: insight?.forecast,
                                accountLabel: insight?.label ?? "", wide: wide,
                                loading: resetNotice.fetching || accounts.connected(.codex).contains {
                                    accounts.codex($0)?.loading == true
                                }, openDetails: { showResetDetails = true },
                                dismissAnnouncement: {
                                    if let announcement = resetAnnouncement { dismissedResetID = announcement.id }
                                }, dismissForecast: {
                                    if let insight { quotaInsights.dismiss(insight) }
                                })
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(orderedProfiles, id: \.orderKey) { profile in
                                    accountCard(profile, width: min(geometry.size.width, 720) - 32)
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
                            freshness.frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 8)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                        .task(id: MobileQuotaInsightModel.RefreshID(queries: queries, minute: Int(context.date.timeIntervalSince1970 / 60))) {
                            await quotaInsights.refresh(queries: queries, now: context.date)
                        }
                    }
                }
                .refreshable {
                    await accounts.refreshAll()
                    if hasConnectedCodex, !isFixtureMode { await resetNotice.refresh() }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if wide {
                        OverviewWideHeader(refresh: refreshUsage, settings: { selected = .init(kind: .settings) })
                    }
                }
                .background { OverviewBackground().ignoresSafeArea() }
                .navigationTitle("AIQuota")
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar(wide ? .hidden : .visible, for: .navigationBar)
                .toolbar {
                    if !wide {
                        ToolbarItem(placement: .topBarTrailing) { refreshButton() }
                        ToolbarItem(placement: .topBarTrailing) { settingsButton() }
                    }
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
            .task(id: "\(scenePhase)-\(hasConnectedCodex)") {
                guard !isFixtureMode, scenePhase == .active, hasConnectedCodex else { return }
                while !Task.isCancelled {
                    await resetNotice.refresh()
                    do { try await Task.sleep(for: .seconds(60)) }
                    catch { return }
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
        .sheet(isPresented: $showResetDetails) {
            ProbeBrowser(url: CodexResetNotice.website)
        }
    }

    private func refreshUsage() {
        MobileAnalytics.shared.manualRefresh()
        Task {
            await accounts.refreshAll()
            if hasConnectedCodex, !isFixtureMode { await resetNotice.refresh() }
        }
    }

    private func refreshButton() -> some View {
        Button(action: refreshUsage) { Image(systemName: "arrow.clockwise") }
            .tint(OverviewStyle.primary)
            .accessibilityLabel("Refresh usage")
    }

    private func settingsButton() -> some View {
        Button { selected = .init(kind: .settings) } label: { Image(systemName: "gearshape") }
            .tint(OverviewStyle.primary)
            .accessibilityLabel("Settings")
    }

    private var hasConnectedCodex: Bool { !accounts.connected(.codex).isEmpty }

    private var resetAnnouncement: CodexResetAnnouncement? {
        guard hasConnectedCodex else { return nil }
        return resetNotice.announcement(dismissedID: dismissedResetID)
    }

    private var orderedProfiles: [AccountProfile] {
        let visible = accounts.profiles.filter { profile in
            accounts.connected(profile.service).contains { $0.id == profile.id }
        }
        return AccountProfile.ordered(visible, by: accountOrder)
    }

    @ViewBuilder private func accountCard(_ profile: AccountProfile, width: CGFloat) -> some View {
        let reading = profile.service == .codex ? accounts.codex(profile)?.reading : accounts.claude(profile)?.reading
        let accountLabel = overviewAccountLabel(profile, plan: reading?.metadata?.displayPlan)
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

    private func overviewAccountLabel(_ profile: AccountProfile, plan: String?) -> String? {
        overviewDisplayAccountLabel(profile.label, serviceName: profile.service == .codex ? "Codex" : "Claude",
                                    plan: plan, showsAccountLabel: accounts.connected(profile.service).count > 1)
    }

    @ViewBuilder private func sheetContent(_ selection: AccountSheetSelection) -> some View {
        switch selection.kind {
        case .settings:
            MultiAccountSettingsView(accounts: accounts, onboarding: onboarding, orderStore: orderStore)
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
        let changed = orderStore?.setAccountOrder(keys) ?? AccountRegistry.setAccountOrder(keys)
        if changed && !isFixtureMode { reloadAccountOrderWidgets() }
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
