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

                // ── Codex ──────────────────────────────────────────────
                if viewModel.isCodexEnrolled {
                    Section("Codex") {
                        serviceRow(logo: "logo-openai",
                                   isOn: sectionsEnabled ? $vm.settings.notifications.codexEnabled : .constant(false))

                        if sectionsEnabled && vm.settings.notifications.codexEnabled {
                            subHeader("5-hour window")
                            Toggle("Threshold alerts", isOn: $vm.settings.notifications.codex5hThresholdAlerts)
                            Toggle("Window reset",     isOn: $vm.settings.notifications.codex5hReset)

                            subHeader("Weekly usage")
                            Toggle("Threshold alerts", isOn: $vm.settings.notifications.codexWeeklyThresholdAlerts)
                            Toggle("Weekly reset",     isOn: $vm.settings.notifications.codexReset)
                        }
                    }
                    .disabled(!sectionsEnabled)
                    .opacity(sectionsEnabled ? 1 : 0.45)
                }

                // ── Claude Code ────────────────────────────────────────
                if viewModel.isClaudeEnrolled {
                    Section("Claude Code") {
                        serviceRow(logo: "logo-claude",
                                   isOn: sectionsEnabled ? $vm.settings.notifications.claudeEnabled : .constant(false))

                        if sectionsEnabled && vm.settings.notifications.claudeEnabled {
                            subHeader("5-hour window")
                            Toggle("Threshold alerts", isOn: $vm.settings.notifications.claude5hThresholdAlerts)
                            Toggle("Window reset",     isOn: $vm.settings.notifications.claude5hReset)

                            subHeader("7-day window")
                            Toggle("Threshold alerts", isOn: $vm.settings.notifications.claude7dThresholdAlerts)
                            Toggle("Period reset",     isOn: $vm.settings.notifications.claude7dReset)
                        }
                    }
                    .disabled(!sectionsEnabled)
                    .opacity(sectionsEnabled ? 1 : 0.45)
                }

                if viewModel.enrolledServices.isEmpty {
                    Section {
                        Text("Sign in to a service on the previous step to configure thresholds.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sectionsEnabled)
        }
        .task { await checkPermission() }
        .onChange(of: viewModel.settings) { viewModel.saveSettings() }
    }

    // MARK: - Helpers

    /// Service row: logo on the left, enable/disable switch on the right.
    /// The service name is provided by the enclosing Section title.
    @ViewBuilder
    private func serviceRow(logo: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(logo)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
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
