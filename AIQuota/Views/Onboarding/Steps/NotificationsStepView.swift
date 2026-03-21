// AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift
import SwiftUI
import UserNotifications
import AIQuotaKit

struct NotificationsStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var permissionGranted = false
    @State private var codexExpanded  = false
    @State private var claudeExpanded = false

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
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    permissionGranted = false
                                    codexExpanded  = false
                                    claudeExpanded = false
                                }
                            }
                        }
                }

                // Service sections — always visible; collapsed + dimmed until enabled + permitted
                Group {
                    if viewModel.isCodexAuthenticated {
                        Section {
                            if codexExpanded {
                                Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.codexAt15)
                                Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.codexAt5)
                                Toggle("Limit reached",           isOn: $vm.settings.notifications.codexLimitReached)
                                Toggle("Weekly reset",            isOn: $vm.settings.notifications.codexReset)
                            }
                        } header: {
                            ServiceSectionHeader(logoName: "logo-openai", name: "Codex", isExpanded: codexExpanded) {
                                if sectionsEnabled {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        codexExpanded.toggle()
                                    }
                                }
                            }
                        }
                    }

                    if viewModel.isClaudeAuthenticated {
                        Section {
                            if claudeExpanded {
                                Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.claude5hAt15)
                                Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.claude5hAt5)
                                Toggle("Limit reached",           isOn: $vm.settings.notifications.claude5hLimitReached)
                                Toggle("Window reset",            isOn: $vm.settings.notifications.claude5hReset)
                            }
                        } header: {
                            ServiceSectionHeader(logoName: "logo-claude", name: "Claude Code — 5-hour", isExpanded: claudeExpanded) {
                                if sectionsEnabled {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        claudeExpanded.toggle()
                                    }
                                }
                            }
                        }

                        if claudeExpanded {
                            Section {
                                Toggle("80% used (high)",         isOn: $vm.settings.notifications.claude7dAt80)
                                Toggle("95% used (critical)",     isOn: $vm.settings.notifications.claude7dAt95)
                                Toggle("Limit reached",           isOn: $vm.settings.notifications.claude7dLimitReached)
                                Toggle("Period reset",            isOn: $vm.settings.notifications.claude7dReset)
                            } header: {
                                Text("Claude Code — 7-day")
                            }
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
            }
            .formStyle(.grouped)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sectionsEnabled)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: codexExpanded)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: claudeExpanded)
        }
        .task { await checkPermission() }
        .onChange(of: sectionsEnabled) { _, enabled in
            if enabled {
                // Unfurl both sections when permission is granted
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.1)) {
                    codexExpanded  = viewModel.isCodexAuthenticated
                    claudeExpanded = viewModel.isClaudeAuthenticated
                }
            }
        }
        .onChange(of: viewModel.settings) { viewModel.saveSettings() }
    }

    private func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let granted = settings.authorizationStatus == .authorized
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            permissionGranted = granted
        }
    }
}

// MARK: - Service section header with chevron

private struct ServiceSectionHeader: View {
    let logoName: String
    let name: String
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(logoName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                Text(name)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
        }
        .buttonStyle(.plain)
    }
}
