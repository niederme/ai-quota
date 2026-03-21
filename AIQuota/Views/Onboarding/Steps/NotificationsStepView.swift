// AIQuota/Views/Onboarding/Steps/NotificationsStepView.swift
import SwiftUI
import UserNotifications
import AIQuotaKit

struct NotificationsStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var codexExpanded = true
    @State private var claudeExpanded = true

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
                    Text("Enable notifications")
                        .fontWeight(.medium)
                }
                .toggleStyle(.switch)
                .onChange(of: vm.settings.notifications.enabled) { _, enabled in
                    if enabled {
                        Task { await NotificationManager.shared.requestPermission() }
                    }
                }

                if viewModel.settings.notifications.enabled {
                    Divider()

                    // Codex section
                    if viewModel.isCodexAuthenticated {
                        ServiceToggleSection(
                            logoName: "logo-openai",
                            name: "Codex",
                            isExpanded: $codexExpanded
                        ) {
                            Toggle("Less than 15% remaining", isOn: $vm.settings.notifications.codexAt15)
                            Toggle("Less than 5% remaining",  isOn: $vm.settings.notifications.codexAt5)
                            Toggle("Limit reached",           isOn: $vm.settings.notifications.codexLimitReached)
                            Toggle("Weekly reset",            isOn: $vm.settings.notifications.codexReset)
                        }
                    }

                    // Claude section
                    if viewModel.isClaudeAuthenticated {
                        ServiceToggleSection(
                            logoName: "logo-claude",
                            name: "Claude Code",
                            isExpanded: $claudeExpanded
                        ) {
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

// MARK: - Collapsible service section

private struct ServiceToggleSection<Content: View>: View {
    let logoName: String
    let name: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — tap to expand/collapse
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(logoName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)

                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.leading, 30)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}
