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
                .persistentSystemOverlays(.visible)
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
                    showResetDetails = false
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
                case .codexAccount: ProbeView(model: codex, startsSignIn: true)
                case .claudeAccount: ClaudeProbeView(model: claude, startsSignIn: true)
                case .settings:
                    MobileSettingsView(codex: codex, claude: claude, onboarding: onboarding)
                case .codex:
                    if !codex.connected { ProbeView(model: codex) } else {
                    ServiceDetailContent(name: "Codex", icon: "logo-openai", reading: codex.reading,
                        connected: codex.connected, busy: codex.busy, error: codex.error,
                        failure: codex.connectionFailure, history: codex.history, historyUnavailable: codex.historyUnavailable, refresh: { codex.refresh() }) { ProbeView(model: codex, startsSignIn: true) }
                    }
                case .claude:
                    if !claude.connected { ClaudeProbeView(model: claude) } else {
                    ServiceDetailContent(name: "Claude", icon: "logo-claude", reading: claude.reading,
                        connected: claude.connected, busy: claude.busy, error: claude.error,
                        failure: claude.connectionFailure, claudeAccount: claude,
                        refresh: { claude.refresh() }) { ClaudeProbeView(model: claude, startsSignIn: true) }
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
    var identity: AccountPresentation? = nil
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
                if needsReconnect {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Reconnect to update details. Your last reading is retained.",
                              systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.callout).foregroundStyle(OverviewStyle.warning)
                        OverviewReconnectButton(accountName: identity?.title ?? name, disabled: busy) {
                            showAccount = true
                        }
                        .accessibilityIdentifier("detailReconnectButton")
                    }
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
                if error != nil || name == "Codex" {
                    Divider()
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(OverviewStyle.warning)
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
        .navigationTitle(identity?.title ?? name)
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
    private var needsReconnect: Bool { failure == .reconnect || failure == .renewal }
    private var planText: String? {
        if let identity { return identity.subtitle(for: .fullIdentity) }
        let plan = reading?.metadata?.displayPlan.map { "\($0) plan" } ?? "Plan not reported"
        return accountLabel.map { "\($0) · \(plan)" } ?? plan
    }
    @ViewBuilder private var planLabel: some View {
        if let planText {
            Text(planText)
                .font(.subheadline).foregroundStyle(OverviewStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
    var identity: AccountPresentation? = nil
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
            onOpen: onOpen, onReconnect: onReconnect, identity: identity, accountLabel: accountLabel,
            history: history, historyUnavailable: historyUnavailable,
            tokenHistory: tokenHistory, tokenHistoryUnavailable: tokenHistoryUnavailable, tokenHistoryLoading: tokenHistoryLoading)
    }
}

private struct ReconnectButtonAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// The Reconnect action shown on account cards and in the detail sheet,
/// matching the Mac card button. On light glass a tinted bordered fill reads
/// pale, so light mode uses a solid deep-purple fill (white label, ~7:1).
/// Dark mode keeps the tinted fill but with a near-white label: the purple
/// label was 3.5:1 on the pill and read as disabled; #EAD2FF is ~9:1.
struct OverviewReconnectButton: View {
    let accountName: String
    var disabled = false
    /// Cards use a small button with 13 pt text to match their detail lines.
    var compact = false
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .light {
                Button("Reconnect", action: action)
                    .buttonStyle(.borderedProminent).tint(OverviewStyle.reconnectFill)
            } else {
                Button(action: action) {
                    Text("Reconnect").foregroundStyle(OverviewStyle.reconnectInk)
                }
                .buttonStyle(.bordered).tint(OverviewStyle.accent)
            }
        }
        .font(compact ? Font.footnote.weight(.semibold) : nil)
        .controlSize(compact ? .small : .regular)
        .disabled(disabled)
        .accessibilityLabel("Reconnect \(accountName)")
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
    static let controlLavender = Color(red: 0.74, green: 0.61, blue: 0.84)
    /// Light-mode Reconnect fill; the Mac gauge accent (#8530BD).
    static let reconnectFill = Color(red: 0x85 / 255, green: 0x30 / 255, blue: 0xBD / 255)
    /// Dark-mode Reconnect label; the Mac's near-white caption ink (#EAD2FF).
    static let reconnectInk = Color(red: 0xEA / 255, green: 0xD2 / 255, blue: 0xFF / 255)
    static let overviewTrack = Color(uiColor: UIColor { traits in
        (traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black).withAlphaComponent(0.10)
    })
    /// Unused capacity: the empty dial track and token-grid days without usage.
    /// The dial colour at low opacity keeps it purple instead of gray.
    static let overviewEmpty = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xC8 / 255, green: 0x6C / 255, blue: 0xF5 / 255, alpha: 0.16)
            : UIColor(red: 0x85 / 255, green: 0x30 / 255, blue: 0xBD / 255, alpha: 0.12)
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

/// A slightly lifted version of the card surface, legible over the bright header.
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
        .font(.system(size: 20))
        .buttonStyle(.plain)
        .foregroundStyle(OverviewStyle.primary)
        .background { OverviewActionSurface() }
    }
}

struct OverviewActionSurface: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: OverviewStyle.accountRadius)
        shape
            .fill(reduceTransparency
                ? (scheme == .dark ? Color(red: 0.20, green: 0.12, blue: 0.28)
                                   : Color(red: 0.89, green: 0.84, blue: 0.94))
                : OverviewStyle.controlLavender.opacity(scheme == .dark ? 0.12 : 0.10))
            .overlay {
                shape.strokeBorder(OverviewStyle.controlLavender.opacity(contrast == .increased ? 0.50 : 0.18), lineWidth: 1)
            }
            .allowsHitTesting(false)
    }
}

/// Quiet navigation/dismissal chrome shared by account and alert cards.
/// The glyph stays readable while only its surrounding circle is translucent.
struct OverviewControlGlyph: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(contrast == .increased
                ? (scheme == .dark ? Color(red: 0.91, green: 0.84, blue: 0.98)
                                   : Color(red: 0.28, green: 0.16, blue: 0.38))
                : (scheme == .dark ? OverviewStyle.controlLavender : Color(red: 0.43, green: 0.28, blue: 0.54)))
            .frame(width: 20, height: 20)
            .background {
                Circle().fill(reduceTransparency
                    ? (scheme == .dark ? Color(red: 0.23, green: 0.16, blue: 0.30)
                                       : Color(red: 0.87, green: 0.81, blue: 0.92))
                    : OverviewStyle.controlLavender.opacity(contrast == .increased ? 0.24 : 0.14))
            }
            .accessibilityHidden(true)
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
    var identity: AccountPresentation? = nil
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
                // Overlay the Reconnect control as a sibling of the card button,
                // not inside its label, so its tap never also opens the details.
                .overlayPreferenceValue(ReconnectButtonAnchor.self) { anchor in
                    if let anchor, let onReconnect {
                        GeometryReader { geometry in
                            let bounds = geometry[anchor]
                            reconnectButton(onReconnect)
                                .frame(width: bounds.width, height: bounds.height)
                                .position(x: bounds.midX, y: bounds.midY)
                        }
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
                    Text(identity?.service ?? name).unredacted().modifier(OverviewDetailType(title: true, wide: usesWideLayout)).foregroundStyle(OverviewStyle.primary)
                    if hasIssue {
                        // Matches the Mac card: amber says what's wrong, the
                        // purple Reconnect button below is how to fix it.
                        Image(systemName: "exclamationmark.triangle.fill")
                            .modifier(OverviewDetailType(wide: usesWideLayout))
                            .foregroundStyle(OverviewStyle.warning)
                            .padding(.leading, 4)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                    if onOpen != nil {
                        OverviewControlGlyph(symbol: "chevron.right")
                    }
                }
                Text(connected ? (identity?.subtitle ?? ((reading?.metadata?.displayPlan.map { "\($0) plan" } ?? "Plan not reported")
                    + (accountLabel.map { " · \($0)" } ?? ""))) : "Not connected")
                    .modifier(OverviewDetailType(weight: .semibold, wide: usesWideLayout)).foregroundStyle(OverviewStyle.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if connected {
                VStack(alignment: .leading, spacing: 0) {
                    if let windows = reading?.windows, QuotaWindow.allAwaitConfirmation(windows) {
                        // Every window passed at once (a full reset): one line, not one per window.
                        Text(QuotaWindow.combinedAwaitingConfirmation)
                            .modifier(OverviewDetailType(weight: .regular, wide: usesWideLayout))
                            .foregroundStyle(resetTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(reading?.windows ?? []) { window in
                            resetCaption(window, label: window.resetLabel)
                        }
                    }
                    if let budget = reading?.monthlyBudget {
                        // Same purple as the reset captions, matching the Mac card's budget line.
                        Text("\(budget.amountText(budget.used)) of \(budget.amountText(budget.limit))")
                            .modifier(OverviewDetailType(wide: usesWideLayout)).foregroundStyle(resetTextColor)
                        Text(budget.unitLabel).modifier(OverviewDetailType(wide: usesWideLayout))
                            .foregroundStyle(resetTextColor)
                        if let reading, let reset = budget.confirmedResetDescription(readingAt: reading.fetchedAt) {
                            Text(reset).modifier(OverviewDetailType(wide: usesWideLayout))
                                .foregroundStyle(resetTextColor)
                        }
                    }
                }
                if showsReconnectButton, let onReconnect {
                    // Placeholder that reserves the layout slot; the live button
                    // is overlaid outside the card's own Button in `body`.
                    reconnectButton(onReconnect)
                        .hidden()
                        .accessibilityHidden(true)
                        .anchorPreference(key: ReconnectButtonAnchor.self, value: .bounds) { $0 }
                        .padding(.top, 4)
                        .padding(.bottom, 4)
                } else if failure != nil || error != nil || reading == nil || worst >= 100 {
                    Text(statusText).modifier(OverviewDetailType(weight: .regular, wide: usesWideLayout))
                        .foregroundStyle(failure != nil || error != nil ? OverviewStyle.warning : OverviewStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var hasIssue: Bool { connected && (failure != nil || error != nil) }
    private var showsReconnectButton: Bool {
        (failure == .reconnect || failure == .renewal) && onReconnect != nil
    }
    private func reconnectButton(_ action: @escaping () -> Void) -> some View {
        OverviewReconnectButton(accountName: identity?.title ?? name, disabled: busy, compact: true, action: action)
            .accessibilityIdentifier(name == "Codex" ? "codexReconnectButton" : "claudeReconnectButton")
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
                        // One line, "44% 30d", like the Mac dial: the key is the
                        // calendar month's length and takes the ring's tint.
                        Text("\(Int(budget.usedPercent.rounded()))% \(MonthlyBudget.periodLabel(containing: reading?.fetchedAt ?? .now))")
                            .font(.system(size: 16 * scale, weight: .semibold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
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
                .stroke(OverviewStyle.overviewEmpty, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
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
