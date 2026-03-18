import SwiftUI
import ServiceManagement
import AIQuotaKit

struct SettingsView: View {
    @Environment(QuotaViewModel.self) private var viewModel

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
                    Button("Send test notifications") {
                        Task { await viewModel.testNotifications() }
                    }
                    .foregroundStyle(.secondary)

                    Text("Fires all four notification types (2 s apart) to verify they appear.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
