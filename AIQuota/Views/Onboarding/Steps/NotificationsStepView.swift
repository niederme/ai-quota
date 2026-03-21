// AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift
import SwiftUI
import UserNotifications
import AIQuotaKit

struct NotificationsStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications")
                        .font(.title2).fontWeight(.bold)
                    Text("Choose which alerts you'd like to receive.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 28)

                // Master toggle
                Toggle(isOn: $vm.settings.notifications.enabled) {
                    Label("Enable notifications", systemImage: "bell.badge")
                        .fontWeight(.medium)
                }
                .onChange(of: vm.settings.notifications.enabled) { _, enabled in
                    if enabled {
                        Task { await NotificationManager.shared.requestPermission() }
                    }
                }

                if viewModel.settings.notifications.enabled {
                    Divider()

                    // Codex section (only if authenticated)
                    if viewModel.isCodexAuthenticated {
                        NotificationServiceSection(title: "Codex", icon: "brain.fill") {
                            Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.codexAt15)
                            Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.codexAt5)
                            Toggle("Limit reached",           isOn: $vm.settings.notifications.codexLimitReached)
                            Toggle("Weekly reset",            isOn: $vm.settings.notifications.codexReset)
                        }
                    }

                    // Claude section (only if authenticated)
                    if viewModel.isClaudeAuthenticated {
                        NotificationServiceSection(title: "Claude Code", icon: "sparkles") {
                            Text("5-hour window")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                            Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.claude5hAt15)
                            Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.claude5hAt5)
                            Toggle("Limit reached",           isOn: $vm.settings.notifications.claude5hLimitReached)
                            Toggle("Window reset",            isOn: $vm.settings.notifications.claude5hReset)

                            Text("7-day window")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                            Toggle("80% used (high)",         isOn: $vm.settings.notifications.claude7dAt80)
                            Toggle("95% used (critical)",     isOn: $vm.settings.notifications.claude7dAt95)
                            Toggle("Limit reached",           isOn: $vm.settings.notifications.claude7dLimitReached)
                            Toggle("Period reset",            isOn: $vm.settings.notifications.claude7dReset)
                        }
                    }

                    if !viewModel.isCodexAuthenticated && !viewModel.isClaudeAuthenticated {
                        Text("Sign in to a service to configure thresholds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 36)
        }
        .onChange(of: viewModel.settings) { viewModel.saveSettings() }
    }
}

// MARK: - Service section container

private struct NotificationServiceSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Color.brand)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(.leading, 4)
        }
    }
}
