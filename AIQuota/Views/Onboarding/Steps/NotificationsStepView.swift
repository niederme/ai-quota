// AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift
import SwiftUI
import UserNotifications
import AIQuotaKit

struct NotificationsStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var permissionGranted = false
    @State private var permissionDenied = false

    private var notificationControlsEnabled: Bool {
        viewModel.settings.notifications.enabled && permissionGranted
    }

    var body: some View {
        @Bindable var vm = viewModel

        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications")
                    .font(.title2).fontWeight(.bold)
                Text("Choose which alerts you’d like to receive.")
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
                            if enabled && !viewModel.isReadOnlyPreview {
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
                    if viewModel.settings.notifications.enabled && !permissionGranted {
                        Button(permissionDenied ? "Open System Settings…" : "Allow Notifications…") {
                            if permissionDenied {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                            } else {
                                Task {
                                    await NotificationManager.shared.requestPermission()
                                    await checkPermission()
                                }
                            }
                        }
                        .disabled(viewModel.isReadOnlyPreview)
                    }
                }

                if viewModel.settings.notifications.enabled {
                    if viewModel.isCodexEnrolled {
                        Section {
                            OnboardingNotificationServiceRow(
                                service: .codex, logo: "logo-openai",
                                isOn: $vm.settings.notifications.codexEnabled,
                                isEnabled: notificationControlsEnabled,
                                preferences: $vm.settings.notifications
                            )
                        }
                    }
                    if viewModel.isClaudeEnrolled {
                        Section {
                            OnboardingNotificationServiceRow(
                                service: .claude, logo: "logo-claude",
                                isOn: $vm.settings.notifications.claudeEnabled,
                                isEnabled: notificationControlsEnabled,
                                preferences: $vm.settings.notifications
                            )
                        }
                    }
                    if viewModel.enrolledServices.isEmpty {
                        Text("Connect a service on the previous step to configure thresholds.")
                            .foregroundStyle(.secondary)
                    }
                    Section {} footer: {
                        Text("One usage alert per window at your threshold. On Mac, alerts follow the original connection for each service.")
                    }
                }
            }
            .formStyle(.grouped)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: notificationControlsEnabled)
        }
        .task { await checkPermission() }
        .onChange(of: viewModel.settings) { viewModel.saveSettings() }
    }

    private func checkPermission() async {
        if viewModel.isReadOnlyPreview { permissionGranted = true; return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            permissionGranted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            permissionDenied = settings.authorizationStatus == .denied
        }
    }
}

private struct OnboardingNotificationServiceRow: View {
    let service: ServiceType
    let logo: String
    @Binding var isOn: Bool
    let isEnabled: Bool
    @Binding var preferences: NotificationPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 10) {
                    Image(logo).resizable().scaledToFit().frame(width: 18, height: 18)
                    Text(service.displayName).fontWeight(.semibold)
                }
            }
            .toggleStyle(.switch)
            .accessibilityLabel("Allow \(service.displayName) notifications")
            .disabled(!isEnabled)

            NotificationInlineControls(service: service, preferences: $preferences)
                .disabled(!isOn || !isEnabled)
        }
        .padding(.vertical, 6)
    }
}
