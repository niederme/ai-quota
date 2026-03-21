// AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift
import SwiftUI
import UserNotifications
import AIQuotaKit

struct NotificationsStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var permissionGranted = false

    private var sectionsEnabled: Bool {
        viewModel.settings.notifications.enabled && permissionGranted
    }

    var body: some View {
        @Bindable var vm = viewModel

        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications")
                    .font(.title2).fontWeight(.bold)
                Text("Choose which alerts you'd like to receive.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 4)

            // System Settings–style grouped form
            Form {
                // Master toggle
                Section {
                    Toggle("Enable notifications", isOn: $vm.settings.notifications.enabled)
                        .onChange(of: vm.settings.notifications.enabled) { _, enabled in
                            if enabled {
                                Task {
                                    await NotificationManager.shared.requestPermission()
                                    await checkPermission()
                                }
                            } else {
                                permissionGranted = false
                            }
                        }
                }

                // Service sections — always visible, dimmed until enabled + permitted
                Group {
                    if viewModel.isCodexAuthenticated {
                        Section {
                            Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.codexAt15)
                            Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.codexAt5)
                            Toggle("Limit reached",           isOn: $vm.settings.notifications.codexLimitReached)
                            Toggle("Weekly reset",            isOn: $vm.settings.notifications.codexReset)
                        } header: {
                            ServiceSectionHeader(logoName: "logo-openai", name: "Codex")
                        }
                    }

                    if viewModel.isClaudeAuthenticated {
                        Section {
                            Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.claude5hAt15)
                            Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.claude5hAt5)
                            Toggle("Limit reached",           isOn: $vm.settings.notifications.claude5hLimitReached)
                            Toggle("Window reset",            isOn: $vm.settings.notifications.claude5hReset)
                        } header: {
                            ServiceSectionHeader(logoName: "logo-claude", name: "Claude Code — 5-hour")
                        }

                        Section {
                            Toggle("80% used (high)",         isOn: $vm.settings.notifications.claude7dAt80)
                            Toggle("95% used (critical)",     isOn: $vm.settings.notifications.claude7dAt95)
                            Toggle("Limit reached",           isOn: $vm.settings.notifications.claude7dLimitReached)
                            Toggle("Period reset",            isOn: $vm.settings.notifications.claude7dReset)
                        } header: {
                            Text("Claude Code — 7-day")
                        }
                    }

                    if !viewModel.isCodexAuthenticated && !viewModel.isClaudeAuthenticated {
                        Section {
                            Text("Sign in to a service on the previous step to configure thresholds.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!sectionsEnabled)
                .opacity(sectionsEnabled ? 1 : 0.4)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sectionsEnabled)
            }
            .formStyle(.grouped)
        }
        .task { await checkPermission() }
        .onChange(of: viewModel.settings) { viewModel.saveSettings() }
    }

    private func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionGranted = settings.authorizationStatus == .authorized
    }
}

// MARK: - Service section header

private struct ServiceSectionHeader: View {
    let logoName: String
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Image(logoName)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
            Text(name)
        }
    }
}
