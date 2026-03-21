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

            Form {
                // ── Master toggle ───────────────────────────────────────
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
                                }
                            }
                        }
                }

                // ── Service sections: only when master is on + permission granted ──
                if sectionsEnabled {
                    // ── Codex ─────────────────────────────────────────
                    if viewModel.isCodexAuthenticated {
                        Section {
                            serviceRow(logo: "logo-openai", name: "Codex",
                                       isOn: $vm.settings.notifications.codexEnabled)

                            // Sub-toggles collapse when service is OFF
                            if vm.settings.notifications.codexEnabled {
                                Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.codexAt15)
                                Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.codexAt5)
                                Toggle("Limit reached",           isOn: $vm.settings.notifications.codexLimitReached)
                                Toggle("Weekly reset",            isOn: $vm.settings.notifications.codexReset)
                            }
                        }
                    }

                    // ── Claude Code ────────────────────────────────────
                    if viewModel.isClaudeAuthenticated {
                        Section {
                            serviceRow(logo: "logo-claude", name: "Claude Code",
                                       isOn: $vm.settings.notifications.claudeEnabled)

                            // Sub-toggles collapse when service is OFF
                            if vm.settings.notifications.claudeEnabled {
                                subHeader("5-hour window")
                                Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.claude5hAt15)
                                Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.claude5hAt5)
                                Toggle("Limit reached",           isOn: $vm.settings.notifications.claude5hLimitReached)
                                Toggle("Window reset",            isOn: $vm.settings.notifications.claude5hReset)

                                subHeader("7-day window")
                                Toggle("80% used (high)",         isOn: $vm.settings.notifications.claude7dAt80)
                                Toggle("95% used (critical)",     isOn: $vm.settings.notifications.claude7dAt95)
                                Toggle("Limit reached",           isOn: $vm.settings.notifications.claude7dLimitReached)
                                Toggle("Period reset",            isOn: $vm.settings.notifications.claude7dReset)
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
            }
            .formStyle(.grouped)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sectionsEnabled)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.settings.notifications.codexEnabled)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.settings.notifications.claudeEnabled)
        }
        .task { await checkPermission() }
        .onChange(of: viewModel.settings) { viewModel.saveSettings() }
    }

    // MARK: - Helpers

    /// Bold service row: logo + name on the left, switch on the right.
    @ViewBuilder
    private func serviceRow(logo: String, name: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(logo)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text(name)
                .fontWeight(.semibold)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    /// Inline sub-section label.
    @ViewBuilder
    private func subHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
    }

    private func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            permissionGranted = settings.authorizationStatus == .authorized
        }
    }
}
