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
                    onSignIn: { Task { await viewModel.signIn() } }
                )

                ServiceRow(
                    logoName: "logo-claude",
                    name: "Claude Code",
                    subtitle: "Anthropic / claude.ai",
                    isAuthenticated: viewModel.isClaudeAuthenticated,
                    onSignIn: { Task { await viewModel.signInClaude() } }
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            Text("You can connect more services later in Settings.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - Service Row

private struct ServiceRow: View {
    let logoName: String
    let name: String
    let subtitle: String
    let isAuthenticated: Bool
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
