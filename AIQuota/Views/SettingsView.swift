import SwiftUI
import ServiceManagement
import UserNotifications
import AIQuotaKit

struct SettingsView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(UpdaterViewModel.self) private var updater

    private let refreshOptions = [5, 15, 30, 60]

    var body: some View {
        @Bindable var vm = viewModel
        @Bindable var u = updater

        Form {
            // MARK: General
            Section("General") {
                Picker("Refresh every", selection: $vm.settings.refreshIntervalMinutes) {
                    ForEach(refreshOptions, id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Menu bar service", selection: $vm.settings.menuBarService) {
                    ForEach(ServiceType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                LaunchAtLoginToggle()
            }

            // MARK: Notifications
            Section("Notifications") {
                Toggle("Enable notifications", isOn: $vm.settings.notifications.enabled)
                    .onChange(of: vm.settings.notifications.enabled) { _, enabled in
                        if enabled {
                            Task { await NotificationManager.shared.requestPermission() }
                        }
                    }

                if viewModel.settings.notifications.enabled {
                    NotificationStatusRow()
                }
            }

            // MARK: Updates
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $u.automaticallyChecksForUpdates)
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }

            // MARK: Accounts
            Section("Accounts") {
                LabeledContent("Codex") {
                    if viewModel.isCodexAuthenticated {
                        Button("Sign Out", role: .destructive) { viewModel.signOut() }
                    } else {
                        Button("Sign In") { Task { await viewModel.signIn() } }
                    }
                }
                LabeledContent("Claude Code") {
                    if viewModel.isClaudeAuthenticated {
                        Button("Sign Out", role: .destructive) { viewModel.signOutClaude() }
                    } else {
                        Button("Sign In") { Task { await viewModel.signInClaude() } }
                    }
                }
            }

            // MARK: About footer
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
            Section {
                VStack(spacing: 3) {
                    Text("AIQuota \(version) (\(build))")
                        .fontWeight(.medium)
                    Text("Made by John Niedermeyer, with a little help from\nClaude, Codex and friends.")
                        .multilineTextAlignment(.center)
                    Text("Need Help?")
                        .padding(.top, 4)
                    HStack(spacing: 12) {
                        Link("GitHub Issues", destination: URL(string: "https://github.com/niederme/ai-quota/issues")!)
                            .foregroundColor(Color(red: 0.62, green: 0.22, blue: 0.93))
                        Text("·").foregroundStyle(.quaternary)
                        Link("@niederme on X", destination: URL(string: "https://x.com/niederme")!)
                            .foregroundColor(Color(red: 0.62, green: 0.22, blue: 0.93))
                    }
                }
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .navigationTitle("Settings")
        .onChange(of: viewModel.settings) { viewModel.saveSettings() }
        .background(FloatingWindowElevator())
    }
}

// MARK: - Window level helper

private struct FloatingWindowElevator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.level = .floating }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Notification Status

private struct NotificationStatusRow: View {
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        HStack {
            switch status {
            case .authorized:
                Label("Permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Label("Permission denied", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Spacer()
                Button("Open System Settings") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
                    )
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            default:
                Label("Permission not requested yet", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            status = settings.authorizationStatus
        }
    }
}

// MARK: - Launch at Login

private struct LaunchAtLoginToggle: View {
    @State private var isEnabled = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        Toggle("Launch at login", isOn: $isEnabled)
            .onChange(of: isEnabled) { _, newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() }
                    else        { try SMAppService.mainApp.unregister() }
                } catch {
                    isEnabled = !newValue
                }
            }
    }
}
