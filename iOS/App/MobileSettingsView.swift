import SwiftUI
import MobileAccessCore

struct MobileSettingsView: View {
    @Environment(\.setDemoEnabled) private var setDemoEnabled
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 0
    @State private var showOnboarding = false
    @State private var demoOnboarding = OnboardingProgress(isDemo: true)
    @State private var demoRefreshMinutes = 0
    private var setupProgress: OnboardingProgress { codex.isDemo ? demoOnboarding : onboarding }
    private var refreshSelection: Binding<Int> { codex.isDemo ? $demoRefreshMinutes : $refreshMinutes }
    @State private var destination: SettingsDestination?
    private enum SettingsDestination: String, Identifiable {
        case codex, claude, notifications, widgets
        var id: String { rawValue }
    }
    @State private var confirmReset = false
    @State private var resetting = false
    @State private var resetError: String?
    let codex: ProbeModel
    let claude: ClaudeProbeModel
    let onboarding: OnboardingProgress
    var body: some View {
        Form {
            Section {
                Button(codex.isDemo ? "Exit demo" : "Try demo") {
                    setDemoEnabled(!codex.isDemo)
                }
            } header: { Text("Demo") } footer: {
                Text(codex.isDemo ? "The app and widgets show sample usage. Exit to connect your accounts or return to your saved connections." : "Explore sample usage without signing in. Your saved accounts are preserved.")
            }.listRowBackground(OverviewStyle.track)
            Section {
                Picker("Refresh every", selection: refreshSelection) {
                    Text("Auto").tag(0)
                    ForEach([1, 5, 10, 30], id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
            } header: { Text("General") } footer: {
                Text("While the app is open, Auto refreshes every 5 minutes, or every minute near a limit. iOS controls background widget updates. Opening the app also checks for fresh usage.")
            }.listRowBackground(OverviewStyle.track)
            Section {
                Button { destination = .codex } label: {
                    MobileAccountRow(name: "Codex", connected: codex.connected, error: codex.error, updated: codex.reading?.fetchedAt, busy: codex.busy, isDemo: codex.isDemo)
                }
                Button { destination = .claude } label: {
                    MobileAccountRow(name: "Claude Code", connected: claude.connected, error: claude.error, updated: claude.reading?.fetchedAt, busy: claude.busy, isDemo: claude.isDemo)
                }
            } header: { Text("Accounts") } footer: {
                Text("Manage accounts, reconnect, and check when usage last updated.")
            }.listRowBackground(OverviewStyle.track)
            Section { Button("Notifications") { destination = .notifications } }.listRowBackground(OverviewStyle.track)
            Section("Onboarding") {
                Button("Guided Setup…") {
                    setupProgress.replay()
                    showOnboarding = true
                }
                Button("Widgets") { destination = .widgets }
                Button("Reset All Settings…", role: .destructive) { confirmReset = true }.disabled(codex.isDemo)
                if resetting { ProgressView("Resetting…") }
                if let resetError { Text(resetError).font(.callout).foregroundStyle(OverviewStyle.critical) }
            }.listRowBackground(OverviewStyle.track)
            Section("Privacy") {
                MobileAnalyticsConsentControls(surface: .settings, isDemo: codex.isDemo)
                Text("Sign-in credentials stay in this device’s Keychain and are shared with its widgets. Usage is requested directly from each service.")
                    .font(.footnote).foregroundStyle(OverviewStyle.secondary)
            }.listRowBackground(OverviewStyle.track)
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }.listRowBackground(OverviewStyle.track)
        }.disabled(resetting)
        .scrollContentBackground(.hidden)
        .background { BrandSurfaceBackground().ignoresSafeArea() }
        .toolbarBackground(.hidden, for: .navigationBar)
        .foregroundStyle(OverviewStyle.primary)
        .tint(OverviewStyle.accent)
        .confirmationDialog("Clear all Settings and Start Over?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                resetting = true
                resetError = nil
                MobileAnalytics.shared.reset()
                Task {
                    // Prevent any further widget scheduling while account leases settle.
                    MobileResetNotifications.defaults.set(false, forKey: "notifications.enabled")
                    do {
                        try await codex.resetForNewUser()
                        try await claude.resetForNewUser()
                        MobileSettingsReset.clearPreferences()
                        onboarding.reset()
                        onboarding.begin()
                        showOnboarding = true
                    } catch {
                        resetError = "Couldn’t finish resetting. Some connections may already be removed. Try again."
                    }
                    resetting = false
                }
            }
        } message: {
            Text("Signs out of all services, clears cached data, and resets settings to defaults. System notification permissions are not affected.")
        }
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $destination) { destination in
            ServiceAccountSheet {
                switch destination {
                case .codex: ProbeView(model: codex)
                case .claude: ClaudeProbeView(model: claude)
                case .notifications:
                    if codex.isDemo { DemoNotificationsView() } else { MobileNotificationsView() }
                case .widgets: LockScreenSetupView()
                }
            }
        }
        .sheet(isPresented: $showOnboarding, onDismiss: { setupProgress.dismiss() }) {
            OnboardingView(codex: codex, claude: claude, progress: setupProgress)
        }
    }
}

struct MobileAccountRow: View {
    let name: String
    let connected: Bool
    let error: String?
    let updated: Date?
    let busy: Bool
    var isDemo = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name).fontWeight(.semibold).foregroundStyle(.primary)
                    Spacer()
                    if !connected && !busy {
                        Text("Connect").foregroundStyle(OverviewStyle.accent)
                    } else {
                        Text(isDemo ? "Sample account" : busy ? "Refreshing…" : error == nil ? "Connected" : "Needs attention")
                            .foregroundStyle(.secondary)
                    }
                }
                if let updated {
                    Text("Updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if connected || busy {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .font(.body)
    }
}


import UserNotifications

struct MobileNotificationsView: View {
    var body: some View {
        MobileNotificationControls()
            .background { BrandSurfaceBackground().ignoresSafeArea() }
            .toolbarBackground(.hidden, for: .navigationBar)
            .tint(OverviewStyle.accent)
            .navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
    }
}
struct MobileNotificationControls: View {
    @AppStorage(DemoQuotaData.enabledKey, store: DemoQuotaData.defaults) private var isDemo = false
    @AppStorage("notifications.enabled", store: MobileResetNotifications.defaults) private var enabled = false
    @AppStorage("notifications.codex", store: MobileResetNotifications.defaults) private var codex = true
    @AppStorage("notifications.claude", store: MobileResetNotifications.defaults) private var claude = true
    @AppStorage("notifications.error", store: MobileResetNotifications.defaults) private var schedulingError = ""
    @State private var denied = false
    @State private var requesting = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    var readings: [QuotaService: QuotaReading] = Dictionary(uniqueKeysWithValues: QuotaService.allCases.compactMap { service in
        SharedQuotaStore(service).reading().map { (service, $0) }
    })
    var body: some View {
        Form {
            Section {
                Toggle("Enable notifications", isOn: Binding(get: { enabled }, set: { value in
                    enabled = value
                    Task {
                        if value {
                            requesting = true
                            do { enabled = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
                            catch { enabled = false; schedulingError = "Couldn’t enable notifications. Try again." }
                            requesting = false
                        }
                        await check()
                    }
                })).disabled(requesting)
            } footer: {
                if readings.values.allSatisfy({ $0.windows.isEmpty }) {
                    Text("Connect an account to configure alerts. Notifications will be ready when you connect.")
                } else {
                    Text("Choose which alerts you’d like to receive.")
                }
            }.listRowBackground(OverviewStyle.track)
            if enabled {
                serviceGroup("Codex", service: .codex, enabled: $codex)
                serviceGroup("Claude Code", service: .claude, enabled: $claude)
                if readings.values.contains(where: { !$0.windows.isEmpty }) {
                    Section {} footer: {
                        Text("Usage alerts are checked when the app or widgets update. Reset reminders use your last fresh reading and are estimates; open the app to confirm availability.")
                    }
                }
            }
            if denied {
                Section {
                    Button("Open notification settings") { openURL(URL(string: UIApplication.openNotificationSettingsURLString)!) }
                } footer: { Text("Notifications are disabled in iOS Settings.") }
                    .listRowBackground(OverviewStyle.track)
            }
            if !schedulingError.isEmpty {
                Section { Text(schedulingError).foregroundStyle(OverviewStyle.warning) }
                    .listRowBackground(OverviewStyle.track)
            }
        }
        .scrollContentBackground(.hidden)
        .disabled(isDemo)
        .onChange(of: codex) { Task { await MobileResetNotifications.reconcile() } }
        .onChange(of: claude) { Task { await MobileResetNotifications.reconcile() } }
        .task(id: phase) { if phase == .active { await check() } }
    }
    @ViewBuilder
    private func serviceGroup(_ name: String, service: QuotaService, enabled: Binding<Bool>) -> some View {
        if let reading = readings[service], !reading.windows.isEmpty {
            Section {
                Toggle(name, isOn: enabled)
                if enabled.wrappedValue {
                    if let window = reading.shortTerm {
                        MobileWindowAlertControls(service: service, window: "5h", title: window.label + " window")
                    }
                    if let window = reading.weekly {
                        MobileWindowAlertControls(service: service, window: "7d", title: window.label + " window")
                    }
                }
            }.listRowBackground(OverviewStyle.track)
        }
    }

    private func check() async {
        guard !isDemo else { return }
        denied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
        await MobileResetNotifications.reconcile()
    }
}

@MainActor
enum MobileSettingsReset {
    static func clearPreferences(standard: UserDefaults = .standard,
                                 shared: UserDefaults = MobileResetNotifications.defaults) {
        for key in [MobileAnalytics.enabledKey, MobileAnalytics.lastActiveDateKey, "refreshIntervalMinutes", "mobileProbe.codexReading", "mobileProbe.claudeReading", CodexResetNotice.dismissalKey] {
            standard.removeObject(forKey: key)
        }
        for key in ["notifications.enabled", "notifications.codex", "notifications.claude", "notifications.error"] {
            shared.removeObject(forKey: key)
        }
        for service in QuotaService.allCases {
            for window in ["5h", "7d"] {
                for suffix in ["resetMode", "resetThreshold", "usageEnabled", "usageThreshold", "limitEnabled", "usageState"] {
                    shared.removeObject(forKey: "notifications.\(service.rawValue).\(window).\(suffix)")
                }
            }
            MobileResetNotifications.cancel(service)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers:
                [MobileResetNotifications.identifier(service, "5h"), MobileResetNotifications.identifier(service, "7d"), "quota.usage.\(service.rawValue).5h", "quota.usage.\(service.rawValue).7d"])
        }
    }
}

struct MobileWindowAlertControls: View {
    @State private var expanded = true
    @AppStorage private var mode: String
    @AppStorage private var threshold: Double
    @AppStorage private var usageEnabled: Bool
    @AppStorage private var usageThreshold: Double
    @AppStorage private var limitEnabled: Bool
    let title: String
    init(service: QuotaService, window: String, title: String) {
        self.title = title
        let prefix = "notifications.\(service.rawValue).\(window)."
        _mode = AppStorage(wrappedValue: "nearLimit", prefix + "resetMode", store: MobileResetNotifications.defaults)
        _threshold = AppStorage(wrappedValue: 90, prefix + "resetThreshold", store: MobileResetNotifications.defaults)
        _usageEnabled = AppStorage(wrappedValue: true, prefix + "usageEnabled", store: MobileResetNotifications.defaults)
        _usageThreshold = AppStorage(wrappedValue: 85, prefix + "usageThreshold", store: MobileResetNotifications.defaults)
        _limitEnabled = AppStorage(wrappedValue: true, prefix + "limitEnabled", store: MobileResetNotifications.defaults)
    }
    var body: some View {
        DisclosureGroup(title, isExpanded: $expanded) {
            Toggle("Approaching the limit", isOn: $usageEnabled)
            if usageEnabled {
                Stepper("Alert at \(Int(usageThreshold))% used", value: $usageThreshold, in: 5...95, step: 5)
            }
            Toggle("Limit reached", isOn: $limitEnabled)
            Picker("Reset reminders", selection: $mode) {
                Text("Off").tag("off")
                Text("Near the limit").tag("nearLimit")
                Text("Every reset").tag("everyReset")
            }
            if mode == "nearLimit" {
                Stepper("Remind at \(Int(threshold))% used", value: $threshold, in: 5...100, step: 5)
            }
        }
        .onChange(of: mode) { Task { await MobileResetNotifications.reconcile() } }
        .onChange(of: threshold) { Task { await MobileResetNotifications.reconcile() } }
    }
}
