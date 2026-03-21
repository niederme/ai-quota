// AIQuota/Views/Onboarding/Steps/ServicesStepView.swift
import SwiftUI
import AIQuotaKit

struct ServicesStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Connect your services")
                    .font(.title2).fontWeight(.bold)
                Text("Sign in to the services you use.\nYou need at least one to continue.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 36)

            Spacer()

            // Service cards
            HStack(spacing: 16) {
                ServiceCard(
                    name: "Codex",
                    subtitle: "ChatGPT / OpenAI",
                    icon: "brain.fill",
                    isAuthenticated: viewModel.isCodexAuthenticated,
                    signInAction: { Task { await viewModel.signIn() } },
                    signOutAction: { viewModel.signOut() }
                )

                ServiceCard(
                    name: "Claude Code",
                    subtitle: "Anthropic / claude.ai",
                    icon: "sparkles",
                    isAuthenticated: viewModel.isClaudeAuthenticated,
                    signInAction: { Task { await viewModel.signInClaude() } },
                    signOutAction: { viewModel.signOutClaude() }
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Skip hint
            Text("You can add services later in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
    }
}

// MARK: - Service Card

private struct ServiceCard: View {
    let name: String
    let subtitle: String
    let icon: String
    let isAuthenticated: Bool
    let signInAction: () -> Void
    let signOutAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isAuthenticated ? Color.brand.opacity(0.12) : Color.secondary.opacity(0.1))
                    .frame(width: 60, height: 60)

                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundColor(isAuthenticated ? Color.brand : .secondary)
            }

            VStack(spacing: 3) {
                Text(name)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isAuthenticated {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))

                Button("Sign Out", role: .destructive, action: signOutAction)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Sign In", action: signInAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brand)
                    .controlSize(.small)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isAuthenticated)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isAuthenticated ? Color.brand.opacity(0.4) : Color.secondary.opacity(0.15),
                            lineWidth: 1.5
                        )
                )
        )
    }
}
