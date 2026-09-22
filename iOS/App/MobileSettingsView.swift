import SwiftUI
import MobileAccessCore

struct MobileSettingsView: View {
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 0
    @State private var showOnboarding = false
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
                Picker("Refresh every", selection: $refreshMinutes) {
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
                    account("Codex", connected: codex.connected, error: codex.error, updated: codex.reading?.fetchedAt, busy: codex.busy)
                }
                Button { destination = .claude } label: {
                    account("Claude Code", connected: claude.connected, error: claude.error, updated: claude.reading?.fetchedAt, busy: claude.busy)
                }
            } header: { Text("Accounts") } footer: {
                Text("Manage accounts, reconnect, and check when usage last updated.")
            }.listRowBackground(OverviewStyle.track)
            Section { Button("Notifications") { destination = .notifications } }.listRowBackground(OverviewStyle.track)
            Section("Onboarding") {
                Button("Guided Setup…") {
                    onboarding.replay()
                    showOnboarding = true
                }
                Button("Widgets") { destination = .widgets }
                Button("Reset All Settings…", role: .destructive) { confirmReset = true }
                if resetting { ProgressView("Resetting…") }
                if let resetError { Text(resetError).font(.callout).foregroundStyle(OverviewStyle.critical) }
            }.listRowBackground(OverviewStyle.track)
            Section("Privacy") {
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
                case .notifications: MobileNotificationsView()
                case .widgets: LockScreenSetupView()
                }
            }
        }
        .sheet(isPresented: $showOnboarding, onDismiss: { onboarding.dismiss() }) {
            OnboardingView(codex: codex, claude: claude, progress: onboarding)
        }
    }
    private func account(_ name: String, connected: Bool, error: String?, updated: Date?, busy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(name) {
                Text(busy ? "Refreshing…" : !connected ? "Connect" : error == nil ? "Connected" : "Needs attention")
                    .foregroundStyle(OverviewStyle.secondary)
            }
            if let updated {
                Text("Last updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(OverviewStyle.secondary)
            }
        }
    }
}


import UserNotifications

struct MobileNotificationsView: View {
    var body: some View {
        ScrollView { MobileNotificationControls().padding(24) }
            .background { BrandSurfaceBackground().ignoresSafeArea() }
        .toolbarBackground(.hidden, for: .navigationBar)
            .foregroundStyle(OverviewStyle.primary)
            .tint(OverviewStyle.accent)
            .navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
    }
}
struct MobileNotificationControls: View {
    @AppStorage("notifications.enabled", store: MobileResetNotifications.defaults) private var enabled = false
    @AppStorage("notifications.codex", store: MobileResetNotifications.defaults) private var codex = true
    @AppStorage("notifications.claude", store: MobileResetNotifications.defaults) private var claude = true
    @AppStorage("notifications.error", store: MobileResetNotifications.defaults) private var schedulingError = ""
    @State private var denied = false
    @State private var requesting = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Notifications").font(.title.bold())
            Text("Choose which alerts you’d like to receive.").foregroundStyle(OverviewStyle.secondary)
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
            if enabled {
                serviceGroup("Codex", service: .codex, enabled: $codex)
                serviceGroup("Claude Code", service: .claude, enabled: $claude)
                Text("Usage alerts are checked when the app or widgets update. Reset reminders use your last fresh reading and are estimates; open the app to confirm availability.")
                    .font(.footnote).foregroundStyle(OverviewStyle.secondary)
            }
            if denied {
                Text("Notifications are disabled in iOS Settings.").font(.callout)
                Button("Open notification settings") { openURL(URL(string: UIApplication.openNotificationSettingsURLString)!) }
            }
            if !schedulingError.isEmpty { Text(schedulingError).font(.callout).foregroundStyle(OverviewStyle.warning) }
        }
        .onChange(of: codex) { Task { await MobileResetNotifications.reconcile() } }
        .onChange(of: claude) { Task { await MobileResetNotifications.reconcile() } }
        .task(id: phase) { if phase == .active { await check() } }
    }
    private func serviceGroup(_ name: String, service: QuotaService, enabled: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: enabled) { Text(name).font(.headline) }
            if enabled.wrappedValue {
                Divider()
                MobileServiceAlertControls(service: service)
            }
        }
        .padding(16)
        .background(OverviewStyle.track,
                    in: RoundedRectangle(cornerRadius: OverviewStyle.radius, style: .continuous))
    }

    private func check() async {
        denied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
        await MobileResetNotifications.reconcile()
    }
}

@MainActor
enum MobileSettingsReset {
    static func clearPreferences(standard: UserDefaults = .standard,
                                 shared: UserDefaults = MobileResetNotifications.defaults) {
        for key in ["refreshIntervalMinutes", "mobileProbe.codexReading", "mobileProbe.claudeReading"] {
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

struct MobileServiceAlertControls: View {
    let service: QuotaService
    var body: some View {
        VStack(spacing: 16) {
            MobileWindowAlertControls(service: service, window: "5h", title: "5-hour window")
            Divider()
            MobileWindowAlertControls(service: service, window: "7d", title: "7-day window")
        }
    }
}
struct MobileWindowAlertControls: View {
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
        _usageEnabled = AppStorage(wrappedValue: false, prefix + "usageEnabled", store: MobileResetNotifications.defaults)
        _usageThreshold = AppStorage(wrappedValue: 85, prefix + "usageThreshold", store: MobileResetNotifications.defaults)
        _limitEnabled = AppStorage(wrappedValue: false, prefix + "limitEnabled", store: MobileResetNotifications.defaults)
    }
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Approaching the limit", isOn: $usageEnabled)
                if usageEnabled { Stepper("At least \(Int(usageThreshold))% used", value: $usageThreshold, in: 5...95, step: 5) }
                Toggle("Limit reached", isOn: $limitEnabled)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reset reminders").font(.subheadline.weight(.semibold))
                    Picker("Reset reminders", selection: $mode) {
                        Text("Off").tag("off")
                        Text("Only near the limit").tag("nearLimit")
                        Text("Every reset").tag("everyReset")
                    }.pickerStyle(.menu).labelsHidden()
                    if mode == "nearLimit" {
                        Stepper("At least \(Int(threshold))% used", value: $threshold, in: 5...100, step: 5)
                    }
                }.padding(.top, 8)
            }
            .padding(.leading, 12)
            .padding(.top, 16)
            .padding(.bottom, 8)
        } label: {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(OverviewStyle.primary)
                .padding(.vertical, 6)
        }
        .onChange(of: mode) { Task { await MobileResetNotifications.reconcile() } }
        .onChange(of: threshold) { Task { await MobileResetNotifications.reconcile() } }
    }
}
