import SwiftUI

struct MobileSettingsView: View {
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 0
    @State private var showOnboarding = false
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
            }
            Section {
                NavigationLink { ProbeView(model: codex) } label: {
                    account("Codex", connected: codex.connected, error: codex.error, updated: codex.reading?.fetchedAt, busy: codex.busy)
                }
                NavigationLink { ClaudeProbeView(model: claude) } label: {
                    account("Claude", connected: claude.connected, error: claude.error, updated: claude.reading?.fetchedAt, busy: claude.busy)
                }
            } header: { Text("Accounts") } footer: {
                Text("Manage accounts, reconnect, and check when usage last updated.")
            }
            Section { NavigationLink("Notifications") { MobileNotificationsView() } }
            Section("Onboarding") {
                Button("Guided Setup…") {
                    onboarding.replay()
                    showOnboarding = true
                }
                NavigationLink("Lock Screen widgets") { LockScreenSetupView() }
                Button("Reset All Settings…", role: .destructive) { confirmReset = true }
                if resetting { ProgressView("Resetting…") }
                if let resetError { Text(resetError).font(.callout).foregroundStyle(.red) }
            }
            Section("Privacy") {
                Text("Sign-in credentials stay in this device’s Keychain and are shared with its widgets. Usage is requested directly from each service.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }
        }.disabled(resetting)
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
        .sheet(isPresented: $showOnboarding, onDismiss: { onboarding.dismiss() }) {
            OnboardingView(codex: codex, claude: claude, progress: onboarding)
        }
    }
    private func account(_ name: String, connected: Bool, error: String?, updated: Date?, busy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(name) {
                Text(busy ? "Updating…" : !connected ? "Connect" : error == nil ? "Connected" : "Needs attention")
                    .foregroundStyle(.secondary)
            }
            if let updated {
                Text("Last updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}


import UserNotifications

struct MobileNotificationsView: View {
    var body: some View {
        ScrollView { MobileNotificationControls().padding(24) }
            .background(Color(uiColor: .systemGroupedBackground))
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
            Text("Get a reminder when a reset is expected.").foregroundStyle(.secondary)
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
                Toggle("Codex", isOn: $codex)
                Toggle("Claude", isOn: $claude)
                Text("5-hour and 7-day reset reminders use your last fresh reading. They are estimates; open the app to confirm availability.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if denied {
                Text("Notifications are disabled in iOS Settings.").font(.callout)
                Button("Open notification settings") { openURL(URL(string: UIApplication.openNotificationSettingsURLString)!) }
            }
            if !schedulingError.isEmpty { Text(schedulingError).font(.callout).foregroundStyle(.orange) }
        }
        .onChange(of: codex) { Task { await MobileResetNotifications.reconcile() } }
        .onChange(of: claude) { Task { await MobileResetNotifications.reconcile() } }
        .task(id: phase) { if phase == .active { await check() } }
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
            MobileResetNotifications.cancel(service)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers:
                [MobileResetNotifications.identifier(service, "5h"), MobileResetNotifications.identifier(service, "7d")])
        }
    }
}
