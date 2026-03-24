// AIQuota/Views/Onboarding/Steps/ServicesStepView.swift
import SwiftUI
import AIQuotaKit

struct ServicesStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("Connect your services")
                    .font(.title).fontWeight(.bold)
                Text("Sign in to the services you use.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 32)

            // Service rows
            VStack(spacing: 12) {
                ServiceRow(
                    logoName: "logo-openai",
                    name: "Codex",
                    subtitle: "ChatGPT / OpenAI",
                    isAuthenticated: viewModel.isCodexAuthenticated,
                    isRestoring: viewModel.isRestoringSession,
                    onSignIn: { Task { await viewModel.signIn() } }
                )

                ServiceRow(
                    logoName: "logo-claude",
                    name: "Claude Code",
                    subtitle: "Anthropic / claude.ai",
                    isAuthenticated: viewModel.isClaudeAuthenticated,
                    isRestoring: viewModel.isRestoringSession,
                    onSignIn: { Task { await viewModel.signInClaude() } }
                )
            }
            .padding(.horizontal, 32)

            if viewModel.isCodexAuthenticated && viewModel.isClaudeAuthenticated {
                MenuBarDefaultPicker(
                    selection: viewModel.settings.menuBarService,
                    onSelect: { service in
                        viewModel.settings.menuBarService = service
                        viewModel.saveSettings()
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer()

            Text("You can connect more services later in Settings.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85),
                   value: viewModel.isCodexAuthenticated && viewModel.isClaudeAuthenticated)
    }
}

// MARK: - Service Row

private struct ServiceRow: View {
    let logoName: String
    let name: String
    let subtitle: String
    let isAuthenticated: Bool
    let isRestoring: Bool
    let onSignIn: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Logo
            Image(logoName)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .padding(10)
                .background(
                    Circle()
                        .fill(isAuthenticated
                              ? Color.brand.opacity(0.1)
                              : Color.secondary.opacity(0.08))
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            isAuthenticated ? Color.brand.opacity(0.3) : Color.clear,
                            lineWidth: 1.5
                        )
                )

            // Name + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.title3).fontWeight(.semibold)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status
            if isAuthenticated {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button("Sign In", action: onSignIn)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brand)
                    .controlSize(.small)
                    .disabled(isRestoring)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isAuthenticated)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isAuthenticated
                                ? Color.brand.opacity(0.35)
                                : Color.secondary.opacity(0.12),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Menu Bar Default Picker

private struct MenuBarDefaultPicker: View {
    let selection: ServiceType
    let onSelect: (ServiceType) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Divider()
                .padding(.horizontal, 32)

            Text("Which should show in your menu bar?")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                card(for: .codex,  logoName: "logo-openai")
                card(for: .claude, logoName: "logo-claude")
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func card(for service: ServiceType, logoName: String) -> some View {
        let isSelected = selection == service
        Button { onSelect(service) } label: {
            VStack(spacing: 10) {
                Image(logoName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(isSelected
                                  ? Color.brand.opacity(0.1)
                                  : Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isSelected ? Color.brand.opacity(0.3) : Color.clear,
                                lineWidth: 1.5
                            )
                    )

                Text(service.displayName)
                    .font(.callout).fontWeight(.semibold)

                Circle()
                    .strokeBorder(isSelected ? Color.brand : Color.secondary.opacity(0.3),
                                  lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .fill(Color.brand)
                            .frame(width: 8, height: 8)
                            .opacity(isSelected ? 1 : 0)
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.brand.opacity(0.35) : Color.secondary.opacity(0.12),
                                lineWidth: 1
                            )
                    )
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}
