// AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift
import SwiftUI
import UserNotifications
import AIQuotaKit

struct NotificationsStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var permissionGranted = false

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

                if viewModel.settings.notifications.enabled {
                    Section {
                        if viewModel.isCodexEnrolled {
                            OnboardingNotificationServiceRow(
                                service: .codex,
                                logo: "logo-openai",
                                isOn: $vm.settings.notifications.codexEnabled,
                                isEnabled: notificationControlsEnabled,
                                preferences: $vm.settings.notifications
                            )
                        }

                        if viewModel.isClaudeEnrolled {
                            OnboardingNotificationServiceRow(
                                service: .claude,
                                logo: "logo-claude",
                                isOn: $vm.settings.notifications.claudeEnabled,
                                isEnabled: notificationControlsEnabled,
                                preferences: $vm.settings.notifications
                            )
                        }

                        if viewModel.enrolledServices.isEmpty {
                            Text("Sign in to a service on the previous step to configure thresholds.")
                                .foregroundStyle(.secondary)
                        }
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
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            permissionGranted = settings.authorizationStatus == .authorized
        }
    }
}

private struct OnboardingNotificationServiceRow: View {
    let service: ServiceType
    let logo: String
    @Binding var isOn: Bool
    let isEnabled: Bool
    @Binding var preferences: NotificationPreferences

    @State private var isExpanded = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    toggleExpanded()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Image(logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)

                    Text(service.displayName)
                        .foregroundStyle(.foreground)

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: toggleExpanded)

                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!isEnabled)
            }
            .onHover { isHovering = $0 }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
            )

            if isExpanded {
                OnboardingNotificationInlineControls(service: service, preferences: $preferences)
                    .padding(.leading, 50)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                    .disabled(!isOn || !isEnabled)
                    .opacity(isOn && isEnabled ? 1 : 0.45)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .opacity(isEnabled ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    private func toggleExpanded() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
            isExpanded.toggle()
        }
    }
}

private struct OnboardingNotificationInlineControls: View {
    let service: ServiceType
    @Binding var preferences: NotificationPreferences

    var body: some View {
        switch service {
        case .codex:
            codexControls
        case .claude:
            claudeControls
        }
    }

    @ViewBuilder
    private var codexControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            notificationOptionGroup("5-hour window") {
                notificationCheckbox("Usage alerts", isOn: $preferences.codex5hThresholdAlerts)
                notificationCheckbox("Reset alert", isOn: $preferences.codex5hReset)
            }

            notificationOptionGroup("7-day window") {
                notificationCheckbox("Usage alerts", isOn: $preferences.codexWeeklyThresholdAlerts)
                notificationCheckbox("Reset alert", isOn: $preferences.codexReset)
            }

            notificationOptionGroup("Credits") {
                notificationCheckbox("Top-up events", isOn: $preferences.codexTopUp)
            }
        }
    }

    @ViewBuilder
    private var claudeControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            notificationOptionGroup("5-hour window") {
                notificationCheckbox("Usage alerts", isOn: $preferences.claude5hThresholdAlerts)
                notificationCheckbox("Reset alert", isOn: $preferences.claude5hReset)
            }

            notificationOptionGroup("7-day window") {
                notificationCheckbox("Usage alerts", isOn: $preferences.claude7dThresholdAlerts)
                notificationCheckbox("Reset alert", isOn: $preferences.claude7dReset)
            }
        }
    }

    private func notificationOptionGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
    }

    private func notificationCheckbox(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.checkbox)
    }
}
