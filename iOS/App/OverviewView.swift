import SwiftUI
import MobileAccessCore

struct OverviewView: View {
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 0
    @State private var onboarding = OnboardingProgress()
    @State private var showOnboarding = false
    @State private var needsInitialSetup: Bool
    @State private var codex: ProbeModel
    @State private var resetNotice = CodexResetNotice()
    @State private var showResetDetails = false
    @State private var demoResetDismissed = false
    @AppStorage(CodexResetNotice.dismissalKey) private var dismissedResetID = ""
    @State private var navigationID = UUID()
    @State private var selectedService: OverviewService?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var claude: ClaudeProbeModel
    private let isDemo: Bool

    init(isDemo: Bool = false) {
        self.isDemo = isDemo
        let codex = ProbeModel(isDemo: isDemo)
        let claude = ClaudeProbeModel(isDemo: isDemo)
        _codex = State(initialValue: codex)
        _claude = State(initialValue: claude)
        _needsInitialSetup = State(initialValue: !codex.connected && !claude.connected)
    }
    @State private var existingInstallation = UserDefaults.standard.data(forKey: "mobileProbe.codexReading") != nil
        || UserDefaults.standard.data(forKey: "mobileProbe.claudeReading") != nil

    private var resetAnnouncement: CodexResetAnnouncement? {
        if isDemo { return demoResetDismissed ? nil : CodexResetNotice.demoAnnouncement }
        return resetNotice.announcement(dismissedID: dismissedResetID)
    }

    private var hasConnectedService: Bool { codex.connected || claude.connected }

    var body: some View {
        Group {
            if needsInitialSetup {
                OnboardingView(codex: codex, claude: claude, progress: onboarding,
                               allowsDeferral: false, onFinish: { needsInitialSetup = false })
                    .onAppear { onboarding.resumeRequiredSetup(hasConnectedService: hasConnectedService) }
            } else {
                dashboard
            }
        }
        .onAppear {
            MobileAnalytics.shared.observeServices(codex: codex.connected, claude: claude.connected, isDemo: isDemo)
            MobileAnalytics.shared.recordLaunchIfNeeded()
            if scenePhase == .active { MobileAnalytics.shared.recordDailyActiveIfNeeded() }
        }
        .onChange(of: codex.connected) { _, _ in updateAnalyticsServices() }
        .onChange(of: claude.connected) { _, _ in updateAnalyticsServices() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { MobileBackgroundRefresh.shared.scheduleNext() }
            if phase == .active { MobileAnalytics.shared.recordDailyActiveIfNeeded() }
        }
        .onChange(of: hasConnectedService) { _, connected in
            if !connected {
                selectedService = nil
                showOnboarding = false
                onboarding.replay()
                needsInitialSetup = true
            }
        }
    }

    private func updateAnalyticsServices() {
        MobileAnalytics.shared.observeServices(codex: codex.connected, claude: claude.connected, isDemo: isDemo)
    }

    private func refreshUsage() {
        MobileAnalytics.shared.manualRefresh()
        codex.refresh()
        claude.refresh()
    }

    private var dashboard: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = min(geometry.size.width, 720) - 32 >= 600 && !typeSize.isAccessibilitySize
                OverviewScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if isDemo { DemoBanner() }
                        if codex.connected, let announcement = resetAnnouncement {
                            CodexResetNoticeBanner(announcement: announcement, openDetails: { showResetDetails = true }, dismiss: {
                                if isDemo { demoResetDismissed = true }
                                else { dismissedResetID = announcement.id }
                            }, loading: codex.loading || claude.loading || resetNotice.fetching, wide: wide)
                        }
                        if codex.connected {
                            ProviderDialCard(name: "Codex", icon: "logo-openai", availableWidth: min(geometry.size.width, 720) - 32, reading: codex.reading,
                                             connected: codex.connected, busy: codex.loading, error: codex.error, failure: codex.connectionFailure,
                                             history: codex.history, historyUnavailable: codex.historyUnavailable,
                                             tokenHistory: codex.tokenHistory, tokenHistoryUnavailable: codex.tokenHistoryUnavailable, tokenHistoryLoading: codex.tokenHistoryLoading || (codex.busy && codex.tokenHistory == nil),
                                             onReconnect: { selectedService = .codexAccount }) {
                                selectedService = .codex
                            }
                        }
                        if claude.connected {
                            ProviderDialCard(name: "Claude", icon: "logo-claude", availableWidth: min(geometry.size.width, 720) - 32, reading: claude.reading,
                                             connected: claude.connected, busy: claude.loading, error: claude.error, failure: claude.connectionFailure,
                                             onReconnect: { selectedService = .claudeAccount }) {
                                selectedService = .claude
                            }
                        }
                        overviewFreshness.frame(maxWidth: .infinity).padding(.top, 8)

                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .refreshable {
                    MobileAnalytics.shared.manualRefresh()
                    async let first: Void = codex.refreshAndWait()
                    async let second: Void = claude.refreshAndWait()
                    _ = await (first, second)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if wide {
                        OverviewWideHeader(refreshing: codex.loading || claude.loading,
                                           refreshDisabled: codex.busy || claude.busy,
                                           refresh: refreshUsage,
                                           settings: { selectedService = .settings })
                    }
                }
                .background { OverviewBackground().ignoresSafeArea() }
                .navigationTitle("AIQuota")
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar(wide ? .hidden : .visible, for: .navigationBar)
                .toolbar {
                    if !wide {
                        OverviewActionsToolbar(refreshing: codex.loading || claude.loading,
                                               refreshDisabled: codex.busy || claude.busy,
                                               refresh: refreshUsage,
                                               settings: { selectedService = .settings })
                    }
                }
            }
            .onOpenURL { url in
                guard url.scheme == "aiquota-probe" else { return }
                if url.host == "overview" {
                    selectedService = nil
                    navigationID = UUID()
                    codex.refreshOnOpen()
                    claude.refreshOnOpen()
                }
                if url.host == "codex" { selectedService = .codex; codex.refreshOnOpen() }
                if url.host == "claude" { selectedService = .claude; claude.refreshOnOpen() }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                codex.refreshOnOpen()
                claude.refreshOnOpen()
                if !isDemo { await MobileResetNotifications.reconcile() }
            }
            .task(id: "\(scenePhase)-\(refreshMinutes)") {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    let windows = [codex.reading?.shortTerm, codex.reading?.weekly,
                                   claude.reading?.shortTerm, claude.reading?.weekly]
                    let percentages = windows.compactMap { $0?.usedPercent } +
                        [codex.reading?.monthlyBudget?.usedPercent,
                         claude.reading?.monthlyBudget?.usedPercent].compactMap { $0 }
                    let nearLimit = percentages.contains { $0 >= 85 }
                    let minutes = refreshMinutes == 0 ? (nearLimit ? 1 : 5) : max(1, refreshMinutes)
                    do { try await Task.sleep(for: .seconds(minutes * 60)) }
                    catch { return }
                    async let first: Void = codex.refreshAndWait()
                    async let second: Void = claude.refreshAndWait()
                    _ = await (first, second)
                }
            }
            .task(id: "\(scenePhase)-\(codex.connected)") {
                guard !isDemo, scenePhase == .active, codex.connected else { return }
                while !Task.isCancelled {
                    await resetNotice.refresh()
                    do { try await Task.sleep(for: .seconds(60)) }
                    catch { return }
                }
            }
        }.id(navigationID).tint(OverviewStyle.accent)
        .task {
            guard !isDemo else { return }
            showOnboarding = onboarding.shouldPresent(
                hasExistingAccount: codex.connected || claude.connected
                    || codex.reading != nil || claude.reading != nil,
                hasExistingInstallation: existingInstallation)
        }
        .sheet(item: $selectedService) { service in
            ServiceAccountSheet(showsClose: service == .settings || service == .codexAccount || service == .claudeAccount || (service == .codex ? !codex.connected : !claude.connected)) {
                switch service {
                case .codexAccount: ProbeView(model: codex)
                case .claudeAccount: ClaudeProbeView(model: claude)
                case .settings:
                    MobileSettingsView(codex: codex, claude: claude, onboarding: onboarding)
                case .codex:
                    if !codex.connected { ProbeView(model: codex) } else {
                    ServiceDetailContent(name: "Codex", icon: "logo-openai", reading: codex.reading,
                        connected: codex.connected, busy: codex.busy, error: codex.error,
                        failure: codex.connectionFailure, history: codex.history, historyUnavailable: codex.historyUnavailable, refresh: { codex.refresh() }) { ProbeView(model: codex) }
                    }
                case .claude:
                    if !claude.connected { ClaudeProbeView(model: claude) } else {
                    ServiceDetailContent(name: "Claude", icon: "logo-claude", reading: claude.reading,
                        connected: claude.connected, busy: claude.busy, error: claude.error,
                        failure: claude.connectionFailure, claudeAccount: claude,
                        refresh: { claude.refresh() }) { ClaudeProbeView(model: claude) }
                    }
                }
            }
        }
        .sheet(isPresented: $showOnboarding, onDismiss: { onboarding.dismiss() }) {
            OnboardingView(codex: codex, claude: claude, progress: onboarding)
        }
        .sheet(isPresented: $showResetDetails) {
            ProbeBrowser(url: CodexResetNotice.website)
        }
    }
    private var overviewFreshness: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let failed = codex.error != nil || codex.connectionFailure != nil
                || claude.error != nil || claude.connectionFailure != nil
            VStack(spacing: 4) {
                if isDemo {
                    Text("Sample usage · No live account data").font(.footnote).foregroundStyle(OverviewStyle.secondary)
                } else if failed {
                    freshness("Codex", reading: codex.reading, connected: codex.connected, busy: codex.loading,
                              failed: codex.error != nil || codex.connectionFailure != nil, at: context.date)
                    freshness("Claude", reading: claude.reading, connected: claude.connected, busy: claude.loading,
                              failed: claude.error != nil || claude.connectionFailure != nil, at: context.date)
                } else if codex.loading || claude.loading {
                    Text("Refreshing…")
                } else if let oldest = [codex.reading, claude.reading].compactMap({ $0?.fetchedAt }).min() {
                    Text(overviewFreshnessLabel(oldest, at: context.date, saved: false)
                        .replacingOccurrences(of: "Updated", with: "Refreshed")
                        .replacingOccurrences(of: "Older reading ·", with: "Refreshed"))
                } else {
                    Text("Connect a service to see your usage.")
                }
            }
            .font(.footnote).foregroundStyle(OverviewStyle.secondary)
            .multilineTextAlignment(.center)
        }
    }
    @ViewBuilder private func freshness(_ name: String, reading: QuotaReading?, connected: Bool,
                                        busy: Bool, failed: Bool, at now: Date) -> some View {
        if connected || reading != nil {
            if busy {
                Text("\(name) refreshing…")
            } else if let reading {
                let updated = overviewFreshnessLabel(reading.fetchedAt, at: now, saved: failed)
                Text(failed ? "\(name) couldn’t update · \(updated)" : "\(name) \(updated.lowercased())")
            } else {
                Text("\(name) · No usage received yet")
            }
        }
    }



}

private enum OverviewService: String, Identifiable {
    case codex, claude, settings, codexAccount, claudeAccount
    var id: String { rawValue }
}

struct AccountConnectionForm: View {
    let plan: String?
    let updated: Date?
    let busy: Bool
    let needsReconnect: Bool
    let error: String?
    var updatesPaused = false
    let retry: () -> Void
    let reconnect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: needsReconnect ? "Sign-in required" : "Connected")
                if let plan { LabeledContent("Plan", value: plan).fixedSize(horizontal: false, vertical: true) }
                if !needsReconnect, error != nil, !updatesPaused {
                    Button("Retry update", action: retry)
                }
            } footer: {
                if !needsReconnect, let error {
                    Text(updatesPaused ? "Updates temporarily paused. Your account is still connected."
                         : "\(error) Your account is still connected.")
                }
            }.listRowBackground(OverviewStyle.track)
            if needsReconnect {
                Section {
                    Button("Reconnect", action: reconnect)
                } footer: {
                    if let error { Text(error) }
                }.listRowBackground(OverviewStyle.track)
            }
            Section {
                Button("Disconnect", role: .destructive, action: disconnect)
                    .foregroundStyle(OverviewStyle.critical)
            }.listRowBackground(OverviewStyle.track)
        }
        .disabled(busy)
        .scrollContentBackground(.hidden)
        .background { BrandSurfaceBackground().ignoresSafeArea() }
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(OverviewStyle.accent)
    }
}

/// Close only after this presentation observes a new, confirmed sign-in.
/// Existing accounts and unsuccessful attempts remain available for inspection or retry.
struct DismissAfterAccountConnection: ViewModifier {
    let completionID: UUID?
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.onChange(of: completionID) { _, completed in
            if completed != nil { dismiss() }
        }
    }
}

struct ServiceAccountSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    var showsClose = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    if showsClose {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                            .tint(OverviewStyle.primary)
                            .accessibilityLabel("Close")
                    }
                    }
                }
        }
        .tint(OverviewStyle.accent)
        .presentationBackground(OverviewStyle.base)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct ServiceDetailContent<Account: View>: View {
    let name: String
    let icon: String
    let reading: QuotaReading?
    let connected: Bool
    let busy: Bool
    let error: String?
    let failure: SharedQuotaStore.Failure?
    var accountLabel: String? = nil
    var history: CodexUsageHistory? = nil
    var historyUnavailable = false
    var claudeAccount: ClaudeProbeModel? = nil
    let refresh: () -> Void
    @ViewBuilder var account: () -> Account
    @State private var showAccount = false
    @State private var showResetWebsite = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    planLabel
                    if let reading {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text("Allowance · " + overviewFreshnessLabel(reading.fetchedAt, at: context.date,
                                 saved: failure != nil || error != nil))
                                .font(.footnote).foregroundStyle(OverviewStyle.secondary)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if failure == .reconnect || failure == .renewal {
                    Label("Reconnect to update details. Your last reading is retained.",
                          systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.callout).foregroundStyle(OverviewStyle.warning)
                } else if failure != nil, error == nil {
                    Label("Couldn’t update details. Your last reading is retained.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(OverviewStyle.warning)
                }
                if name == "Codex", history == nil || history?.days.contains(where: { $0.credits != nil }) == true {
                    CodexAnalyticsView(reading: reading, history: history,
                                       historyUnavailable: historyUnavailable, busy: busy, refresh: refresh)
                } else if name == "Claude",
                          reading?.claudeBreakdown != nil || (busy && reading?.monthlyBudget == nil) {
                    ClaudeAnalyticsView(reading: reading, busy: busy,
                                        failed: failure != nil || error != nil, refresh: refresh)
                }
                if name == "Claude", reading?.monthlyBudget != nil, let claudeAccount, !claudeAccount.isDemo {
                    ClaudeEnterpriseDetailView(account: claudeAccount)
                }
                if error != nil || failure == .reconnect || failure == .renewal || name == "Codex" {
                    Divider()
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(OverviewStyle.warning)
                }
                if failure == .reconnect || failure == .renewal {
                    Button { showAccount = true } label: {
                        Label("Reconnect \(name)", systemImage: "person.crop.circle")
                    }
                }
                if name == "Codex" {
                    Button { showResetWebsite = true } label: {
                        Label("Check Codex resets", systemImage: "arrow.up.right")
                    }
                    .accessibilityHint("Opens Codex Resets in the in-app browser")
                }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .background { BrandSurfaceBackground().ignoresSafeArea() }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle(name)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(busy || !connected)
                    .tint(OverviewStyle.primary)
            }
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .tint(OverviewStyle.primary)
                    .accessibilityLabel("Close")
            }
        }
        .sheet(isPresented: $showAccount) {
            ServiceAccountSheet { account() }
        }
        .sheet(isPresented: $showResetWebsite) {
            ProbeBrowser(url: CodexResetNotice.website)
        }
    }
    private var planText: String {
        let plan = reading?.metadata?.displayPlan.map { "\($0) plan" } ?? "Plan not reported"
        return accountLabel.map { "\($0) · \(plan)" } ?? plan
    }
    private var planLabel: some View {
        Text(planText)
            .font(.subheadline).foregroundStyle(OverviewStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

}

struct UsageLoadingState: ViewModifier {
    let loading: Bool
    var label = "Updating usage"
    func body(content: Content) -> some View {
        if loading {
            content.redacted(reason: .placeholder)
                .disabled(true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        } else {
            content
        }
    }
}

/// Preserve the symbol's native size and baseline while keeping its placeholder round.
struct OverviewCircularSymbol: View {
    let systemName: String
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        Image(systemName: systemName)
            .font(.title3)
            .opacity(redactionReasons.contains(.placeholder) ? 0 : 1)
            .overlay {
                if redactionReasons.contains(.placeholder) {
                    Circle().fill(OverviewStyle.track)
                }
            }
            .unredacted()
    }
}

private struct ChartLoadingState: ViewModifier {
    let loading: Bool
    var history = false
    func body(content: Content) -> some View {
        content.opacity(loading ? 0 : 1)
            .overlay {
                if loading {
                    if history {
                        VStack(spacing: 8) {
                            HStack(alignment: .bottom, spacing: 4) {
                                ForEach(0..<30, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 2).fill(OverviewStyle.track)
                                        .frame(height: 20)
                                }
                            }.frame(maxHeight: .infinity, alignment: .bottom)
                            HStack {
                                RoundedRectangle(cornerRadius: 3).fill(OverviewStyle.track).frame(width: 38, height: 10)
                                Spacer()
                                RoundedRectangle(cornerRadius: 3).fill(OverviewStyle.track).frame(width: 30, height: 10)
                            }
                        }.accessibilityHidden(true)
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(OverviewStyle.track)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityHidden(loading)
    }
}

struct BrandSurfaceBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .top) {
            OverviewStyle.base
            if !reduceTransparency {
                RadialGradient(
                    colors: [OverviewStyle.accent.opacity(scheme == .dark ? 0.14 : 0.08), .clear],
                    center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 210
                )
                .frame(height: 320)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ProviderDialCard: View {
    let name: String
    let icon: String
    let availableWidth: CGFloat
    let reading: QuotaReading?
    let connected: Bool
    let busy: Bool
    let error: String?
    var failure: SharedQuotaStore.Failure? = nil
    var accountLabel: String? = nil
    var history: CodexUsageHistory? = nil
    var historyUnavailable = false
    var tokenHistory: CodexTokenHistory? = nil
    var tokenHistoryUnavailable = false
    var tokenHistoryLoading: Bool? = nil
    var onReconnect: (() -> Void)? = nil
    let onOpen: () -> Void
    var body: some View {
        ProviderDialCardContent(name: name, icon: icon, availableWidth: availableWidth,
            reading: reading, connected: connected, busy: busy, error: error, failure: failure,
            onOpen: onOpen, onReconnect: onReconnect, accountLabel: accountLabel,
            history: history, historyUnavailable: historyUnavailable,
            tokenHistory: tokenHistory, tokenHistoryUnavailable: tokenHistoryUnavailable, tokenHistoryLoading: tokenHistoryLoading)
    }
}

/// Shared semantic colors; overview cards mirror the Mac highlighted row surface.
enum OverviewStyle {
    static let accent = Color("OverviewAccent")
    static let resetAccent = Color("OverviewResetAccent")
    static let warning = Color("OverviewWarning")
    static let critical = Color("OverviewCritical")
    static let primary = Color("OverviewPrimary")
    static let secondary = Color("OverviewSecondary")
    static let tertiary = Color("OverviewTertiary")
    static let track = Color(uiColor: .quaternarySystemFill)
    static let base = Color("OverviewBase")
    static let radius: CGFloat = 28
    static let accountRadius: CGFloat = 24
    static let glass = accent.opacity(0.06)
    static let glassHighlight = accent.opacity(0.10)
    static let overviewTrack = Color(uiColor: UIColor { traits in
        (traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black).withAlphaComponent(0.10)
    })
}

/// Align wide-window navigation with the same centered column as the account cards.
struct OverviewWideHeader: View {
    var refreshing = false
    var refreshDisabled = false
    let refresh: () -> Void
    let settings: () -> Void

    var body: some View {
        HStack {
            Text("AIQuota")
                .font(.largeTitle.bold())
                .foregroundStyle(OverviewStyle.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 24)
            OverviewActions(refreshing: refreshing, refreshDisabled: refreshDisabled,
                            refresh: refresh, settings: settings)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("wideOverviewHeader")
    }
}

/// Share the account cards' purple surface across compact and wide navigation.
struct OverviewActions: View {
    var refreshing = false
    var refreshDisabled = false
    let refresh: () -> Void
    let settings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: refresh) {
                ZStack {
                    Image(systemName: "arrow.clockwise").opacity(refreshing ? 0 : 1)
                    ProgressView().opacity(refreshing ? 1 : 0)
                }
                .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(refreshDisabled)
            .accessibilityLabel(refreshing ? "Refreshing usage" : "Refresh usage")
            Button(action: settings) {
                Image(systemName: "gearshape")
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
        }
        .font(.title3)
        .buttonStyle(.plain)
        .foregroundStyle(OverviewStyle.primary)
        .background { OverviewAccountSurface() }
    }
}

struct OverviewActionsToolbar: ToolbarContent {
    var refreshing = false
    var refreshDisabled = false
    let refresh: () -> Void
    let settings: () -> Void

    private var actions: some View {
        OverviewActions(refreshing: refreshing, refreshDisabled: refreshDisabled,
                        refresh: refresh, settings: settings)
    }

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarTrailing) { actions }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { actions }
        }
    }
}

struct OverviewBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                OverviewStyle.base
                if !reduceTransparency {
                    LinearGradient(stops: [
                        .init(color: Color(red: 102/255, green: 31/255, blue: 143/255).opacity(scheme == .dark ? 0.72 : 0.18), location: 0),
                        .init(color: OverviewStyle.accent.opacity(scheme == .dark ? 0.12 : 0.05), location: 0.4),
                        .init(color: .clear, location: 0.7)
                    ], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [OverviewStyle.accent.opacity(scheme == .dark ? 0.35 : 0.12), .clear],
                                   center: .topTrailing, startRadius: 0, endRadius: geometry.size.width * 0.85)
                }
            }
        }.accessibilityHidden(true)
    }
}

struct OverviewCardMaterial: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Regular glass lets the OS apply the user's Liquid Glass appearance and accessibility settings.
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: OverviewStyle.radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: OverviewStyle.radius))
        }
    }
}

/// The Mac row's highlighted surface is the iOS card's resting surface.
struct OverviewAccountSurface: View {
    var pressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: OverviewStyle.accountRadius)
            .fill(OverviewStyle.glass)
            .overlay { OverviewStyle.accent.opacity(pressed ? 0.05 : 0) }
            .overlay(alignment: .top) { OverviewStyle.glassHighlight.frame(height: 1) }
            .clipShape(RoundedRectangle(cornerRadius: OverviewStyle.accountRadius))
            .allowsHitTesting(false)
    }
}

struct OverviewAccountButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { OverviewAccountSurface(pressed: configuration.isPressed) }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct OverviewScrollEdges: Equatable {
    var top = false
    var bottom = false

    init(contentFrame: CGRect = .zero, viewportHeight: CGFloat = 0) {
        let overflow = viewportHeight > 0 && contentFrame.height > viewportHeight + 1
        top = overflow && contentFrame.minY < -1
        bottom = overflow && contentFrame.maxY > viewportHeight + 1
    }
}

/// MacAccountGridView's 24pt mask, with geometry observation that also works on iOS 17.
struct OverviewScrollView<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Namespace private var coordinateSpace
    @State private var scrollEdges = OverviewScrollEdges()
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        let space = coordinateSpace
        let height = viewportHeight
        ScrollView {
            content()
                .onGeometryChange(for: OverviewScrollEdges.self) { geometry in
                    OverviewScrollEdges(contentFrame: geometry.frame(in: .named(space)), viewportHeight: height)
                } action: { scrollEdges = $0 }
        }
        .coordinateSpace(name: space)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .mask {
            GeometryReader { geometry in
                let fade = min(0.5, 24 / max(1, geometry.size.height))
                LinearGradient(stops: [
                    .init(color: scrollEdges.top ? .clear : .black, location: 0),
                    .init(color: .black, location: scrollEdges.top ? fade : 0),
                    .init(color: .black, location: scrollEdges.bottom ? 1 - fade : 1),
                    .init(color: scrollEdges.bottom ? .clear : .black, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

/// Match MacAccountCard's suppression of generated/default account labels.
func overviewDisplayAccountLabel(_ label: String, serviceName: String, plan: String?,
                                 showsAccountLabel: Bool) -> String? {
    let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !label.isEmpty else { return nil }
    if !showsAccountLabel && label.caseInsensitiveCompare("Personal") == .orderedSame { return nil }
    if label.caseInsensitiveCompare(serviceName) == .orderedSame { return nil }
    if let plan, plan.caseInsensitiveCompare("Unknown") != .orderedSame {
        var defaults = ["\(serviceName) \(plan)"]
        if serviceName == "Codex", ["business", "enterprise"].contains(plan.lowercased()) {
            defaults += ["Codex Business", "Codex Enterprise"]
        }
        if defaults.contains(where: { label.caseInsensitiveCompare($0) == .orderedSame }) { return nil }
    }
    let parts = label.split(whereSeparator: \.isWhitespace)
    if parts.count == 2, ["account", "service"].contains(parts[0].lowercased()),
       parts[1].allSatisfy(\.isNumber) { return nil }
    return label
}

/// Mac row line boxes, scaled with Dynamic Type and native accessibility leading.
private struct OverviewDetailType: ViewModifier {
    var title = false
    var weight: Font.Weight = .semibold
    var wide = false
    @ScaledMetric(relativeTo: .title3) private var titleSize = 20.0
    @ScaledMetric(relativeTo: .footnote) private var bodySize = 13.0
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let scale = title ? titleSize / 20 : bodySize / 13
        let size = (title ? (wide ? 22.0 : 20.0) : (wide ? 15.0 : 13.0)) * scale
        let lineHeight = (title ? (wide ? 26.0 : 24.0) : (wide ? 20.0 : 16.0)) * scale
        let nativeHeight = UIFont.systemFont(ofSize: size, weight: weight == .regular ? .regular : .semibold).lineHeight
        content
            .font(.system(size: size, weight: weight))
            .tracking((title ? -0.25 : 0) * scale)
            .padding(.vertical, typeSize.isAccessibilitySize ? 0 : (lineHeight - nativeHeight) / 2)
    }
}

struct ProviderDialCardContent: View {
    let name: String
    let icon: String
    let availableWidth: CGFloat
    let reading: QuotaReading?
    let connected: Bool
    let busy: Bool
    let error: String?
    var failure: SharedQuotaStore.Failure? = nil
    var onOpen: (() -> Void)? = nil
    var onReconnect: (() -> Void)? = nil
    var accountLabel: String? = nil
    var history: CodexUsageHistory? = nil
    var historyUnavailable = false
    var tokenHistory: CodexTokenHistory? = nil
    var tokenHistoryUnavailable = false
    var tokenHistoryLoading: Bool? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var dialSize = 108.0
    private var needsReconnect: Bool { !connected || failure == .reconnect || failure == .renewal }
    private var worst: Double {
        max(max(reading?.shortTerm?.usedPercent ?? 0,
                reading?.weekly?.usedPercent ?? 0),
            reading?.monthlyBudget?.usedPercent ?? 0)
    }
    private var budgetOnly: MonthlyBudget? {
        reading?.windows.isEmpty == true ? reading?.monthlyBudget : nil
    }
    private var tint: Color {
        if !connected { return OverviewStyle.tertiary }
        if worst >= 95 { return OverviewStyle.critical }
        if worst >= 85 { return OverviewStyle.warning }
        return OverviewStyle.accent
    }
    private let secondaryOpacity = 0.7
    private var usesColumns: Bool { !typeSize.isAccessibilitySize && availableWidth - 32 >= min(dialSize, 200) + 180 }
    private var usesWideLayout: Bool { availableWidth >= 600 && !typeSize.isAccessibilitySize }
    private var displayedDialSize: CGFloat { min(dialSize * (usesWideLayout ? 160.0 / 108.0 : 1), 200) }
    private var supportingTextColor: Color {
        usesWideLayout ? OverviewStyle.primary.opacity(0.8) : OverviewStyle.secondary
    }
    private var resetTextColor: Color {
        usesWideLayout && colorScheme == .dark
            ? Color(red: 0.90, green: 0.69, blue: 1.0) : OverviewStyle.resetAccent
    }
    private var historyWidth: CGFloat {
        usesWideLayout ? availableWidth - 40 - displayedDialSize - 40
            : availableWidth - 32 + 2 * Self.strokeOutset
    }

    var body: some View {
        if let open = onOpen ?? onReconnect {
            Button(action: open) { cardContent }
                .buttonStyle(OverviewAccountButtonStyle())
                .accessibilityIdentifier(name == "Codex" ? "codexServiceCard" : "claudeServiceCard")
                .accessibilityHint("Opens \(name) service sheet")
                .accessibilityActions {
                    if needsReconnect, let onReconnect {
                        Button("Reconnect", action: onReconnect)
                    }
                }
        } else {
            cardContent.background { OverviewAccountSurface() }
        }
    }
    private var showsTokenHistory: Bool {
        name == "Codex" && connected && MobileTokenHistoryView.presentation(
            history: tokenHistory, unavailable: tokenHistoryUnavailable,
            loading: tokenHistoryLoading ?? busy, weeks: MobileTokenHistoryView.weekCount(for: historyWidth)) == .populated
    }
    private var cardContent: some View {
        Group {
            if usesWideLayout {
                HStack(alignment: showsTokenHistory ? .top : .center, spacing: 40) {
                    dial.modifier(UsageLoadingState(loading: busy && reading == nil))
                    VStack(alignment: .leading, spacing: 0) {
                        details.modifier(UsageLoadingState(loading: busy && reading == nil))
                        tokenActivity
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    summary.modifier(UsageLoadingState(loading: busy && reading == nil))
                    tokenActivity
                }
            }
        }
        .padding(.horizontal, usesWideLayout ? 20 : 16)
        .padding(.top, usesWideLayout ? 20 : 21)
        .padding(.bottom, usesWideLayout ? 20 : (showsTokenHistory ? 16 : 21))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: OverviewStyle.accountRadius))
    }

    @ViewBuilder private var tokenActivity: some View {
        if showsTokenHistory {
            MobileTokenHistoryView(history: tokenHistory,
                unavailable: tokenHistoryUnavailable, loading: tokenHistoryLoading ?? busy,
                availableWidth: historyWidth)
                .padding(.horizontal, usesWideLayout ? 0 : -Self.strokeOutset)
                .padding(.top, 8)
        }
    }

    private var summary: some View {
        Group {
            if usesColumns {
                HStack(alignment: .top, spacing: 20) { dial; details }
            } else {
                VStack(alignment: .leading, spacing: 12) { dial; details }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            accountSummary
            if connected, reading?.monthlyBudget == nil,
               let spent = reading?.metadata?.usageSpent, spent > 0 { spending(spent) }
        }.padding(.top, usesWideLayout && !showsTokenHistory ? 0 : 8).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var accountSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 4) {
                    Text(name).unredacted().modifier(OverviewDetailType(title: true, wide: usesWideLayout)).foregroundStyle(OverviewStyle.primary)
                    Spacer(minLength: 0)
                    if onOpen != nil {
                        Image(systemName: "chevron.right.circle.fill").font(.system(size: 20))
                            .foregroundStyle(OverviewStyle.tertiary).accessibilityHidden(true)
                    }
                }
                Text(connected ? ((reading?.metadata?.displayPlan.map { "\($0) plan" } ?? "Plan not reported")
                    + (accountLabel.map { " · \($0)" } ?? "")) : "Not connected")
                    .modifier(OverviewDetailType(weight: .semibold, wide: usesWideLayout)).foregroundStyle(OverviewStyle.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if connected {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(reading?.windows ?? []) { window in
                        resetCaption(window, label: window.resetLabel)
                    }
                    if let budget = reading?.monthlyBudget {
                        Text("\(budget.amountText(budget.used)) of \(budget.amountText(budget.limit))")
                            .modifier(OverviewDetailType(wide: usesWideLayout)).foregroundStyle(supportingTextColor)
                        Text(budget.unitLabel).modifier(OverviewDetailType(wide: usesWideLayout))
                            .foregroundStyle(supportingTextColor)
                        if let reset = budget.confirmedResetDescription() {
                            Text(reset).modifier(OverviewDetailType(wide: usesWideLayout))
                                .foregroundStyle(resetTextColor)
                        }
                    }
                }
                if failure != nil || error != nil || reading == nil || worst >= 100 {
                    Text(statusText).modifier(OverviewDetailType(weight: .regular, wide: usesWideLayout))
                        .foregroundStyle(failure != nil || error != nil ? OverviewStyle.warning : OverviewStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var statusText: String {
        if failure == .reconnect || failure == .renewal { return "Reconnect to update" }
        if failure != nil || error != nil { return "Couldn’t update · Saved reading" }
        if reading == nil { return busy ? "Loading allowance…" : "No reading yet" }
        return "Limit reached"
    }
    private func spending(_ amount: Double) -> some View {
        let value = reading?.metadata?.usageCurrency.map { amount.formatted(.currency(code: $0)) }
            ?? amount.formatted(.number.precision(.fractionLength(0...2))) + " credits"
        return Text("Credits used  \(value)")
            .modifier(OverviewDetailType(wide: usesWideLayout)).foregroundStyle(supportingTextColor)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Credits used: \(value)")
    }

    // Mirror MacAccountDial; iOS scales all geometry together, capped at 200pt.
    static let strokeOutset: CGFloat = 5
    private var dialScale: CGFloat { displayedDialSize / 108 }
    private var showsSecondary: Bool { reading?.secondaryWindow != nil || reading == nil }
    var dial: some View {
        let primary = reading?.primaryWindow ?? budgetOnly.map {
            QuotaWindow(usedPercent: $0.usedPercent, durationSeconds: 30 * 86400, resetsAt: $0.resetsAt)
        }
        let scale = dialScale
        return ZStack {
            arc(primary, lineWidth: (showsSecondary ? 7 : 10) * scale, opacity: 1)
            if showsSecondary {
                arc(reading?.secondaryWindow, lineWidth: 7 * scale, opacity: secondaryOpacity)
                    .padding(9 * scale)
            }
            VStack(spacing: 5 * scale) {
                Image(icon).resizable().scaledToFit().frame(width: 18 * scale, height: 18 * scale)
                VStack(spacing: 2 * scale) {
                    if let budget = budgetOnly {
                        Text("\(Int(budget.usedPercent.rounded()))%")
                            .font(.system(size: 16 * scale, weight: .semibold).monospacedDigit())
                        Text("Monthly").font(.system(size: 13 * scale))
                            .foregroundStyle(OverviewStyle.secondary)
                    } else {
                        dialValue(primary, label: primary?.compactLabel ?? "5h")
                    }
                    if showsSecondary {
                        dialValue(reading?.secondaryWindow, label: "7d").opacity(secondaryOpacity)
                    }
                }
            }
            .frame(width: 80 * scale)
            .offset(y: showsSecondary ? -5 * scale : 0)
            .foregroundStyle(tint)
        }
        .frame(width: 108 * scale, height: 108 * scale)
        .padding(.top, Self.strokeOutset * scale)
        .frame(height: 103 * scale, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) allowance used")
        .accessibilityValue(reading?.accessibilitySummary ?? "Allowance unavailable")
    }
    private func dialValue(_ window: QuotaWindow?, label: String) -> some View {
        Text(window.map { "\(Int($0.usedPercent.rounded()))% \(label)" } ?? "— \(label)")
            .font(.system(size: 16 * dialScale, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private func resetCaption(_ window: QuotaWindow?, label: String) -> some View {
        let text: String = {
            guard let window else { return "\(label) not reported" }
            return "\(label) \(window.resetDescription())"
        }()
        return Text(text).modifier(OverviewDetailType(weight: .regular, wide: usesWideLayout)).monospacedDigit()
            .foregroundStyle(window == nil ? supportingTextColor : resetTextColor)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func arc(_ window: QuotaWindow?, lineWidth: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(OverviewStyle.overviewTrack, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            if connected, let window {
                Circle().trim(from: 0, to: 0.75 * min(100, max(0, window.usedPercent)) / 100)
                    .stroke(tint.opacity(opacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
        }.rotationEffect(.degrees(135))
    }

}



func overviewFreshnessLabel(_ fetchedAt: Date, at now: Date, saved: Bool) -> String {
    let elapsed = max(0, Int(now.timeIntervalSince(fetchedAt)))
    let relative = elapsed < 60 ? "just now" : elapsed < 3600 ? "\(elapsed / 60) minute\(elapsed / 60 == 1 ? "" : "s") ago" : "\(elapsed / 3600) hour\(elapsed / 3600 == 1 ? "" : "s") ago"
    if saved { return "Last updated \(relative)" }
    if elapsed >= 1800 { return "Older reading · \(relative)" }
    return "Updated \(relative)"
}
