import SwiftUI
import ServiceManagement
import AIQuotaKit

struct SettingsView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

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

            Section("Menu Bar") {
                Toggle("Show percentage in menu bar", isOn: $vm.settings.showPercentInMenuBar)
            }

            Section("Launch") {
                LaunchAtLoginToggle()
            }

            Section("Account") {
                if viewModel.isAuthenticated {
                    Button("Sign Out", role: .destructive) {
                        viewModel.signOut()
                        dismiss()
                    }
                } else {
                    Button("Sign In with OpenAI") {
                        Task { await viewModel.signIn() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    viewModel.saveSettings()
                    dismiss()
                }
            }
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
