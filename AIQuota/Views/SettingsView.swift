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

        Form {
            Section("Refresh") {
                Picker("Interval", selection: $vm.settings.refreshIntervalMinutes) {
                    ForEach(refreshOptions, id: \.self) { minutes in
                        Text("\(minutes) minutes").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $vm.settings.notificationsEnabled)
                    .onChange(of: vm.settings.notificationsEnabled) { _, enabled in
                        if enabled {
                            Task { await NotificationManager.shared.requestPermission() }
                        }
                    }

                if viewModel.settings.notificationsEnabled {
                    NotificationStatusRow()
                    Button("Send test notifications") {
                        Task { await viewModel.testNotifications() }
                    }
                }
            }

            Section("Updates") {
                @Bindable var u = updater
                Toggle("Automatically check for updates", isOn: $u.automaticallyChecksForUpdates)
                Button("Check for Updates Now") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }

            Section("Launch") {
                LaunchAtLoginToggle()
            }

            Section("Account") {
                if viewModel.isAuthenticated {
                    Button("Sign Out", role: .destructive) {
                        viewModel.signOut()
                    }
                } else {
                    Button("Sign In with OpenAI") {
                        Task { await viewModel.signIn() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .navigationTitle("Settings")
        .onChange(of: viewModel.settings) {
            viewModel.saveSettings()
        }
    }
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
            case .notDetermined:
                Label("Permission not requested yet", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            default:
                Label("Unknown status", systemImage: "questionmark.circle")
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
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    isEnabled = !newValue
                }
            }
    }
}
