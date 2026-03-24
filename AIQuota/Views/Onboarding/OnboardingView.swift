// AIQuota/Views/Onboarding/OnboardingView.swift
import SwiftUI
import AIQuotaKit

// MARK: - Brand color

extension Color {
    static let brand = Color(red: 0.62, green: 0.22, blue: 0.93)
}

// MARK: - Steps

enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome       = 0
    case services      = 1
    case notifications = 2
    case widgets       = 3
    case done          = 4
}

// MARK: - OnboardingView

struct OnboardingView: View {
    @Environment(QuotaViewModel.self) private var viewModel

    @State private var step: OnboardingStep = .welcome
    @State private var direction: Int = 1   // +1 forward, -1 backward

    // Fixed window size
    static let width: CGFloat  = 520
    static let height: CGFloat = 580

    var body: some View {
        VStack(spacing: 0) {
            // Content area — fills available space
            ZStack {
                stepView(for: step)
                    .id(step)
                    .transition(slideTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: step)

            // Navigation bar — material surface separates it from content naturally
            navigationBar
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
        }
        .frame(width: Self.width, height: Self.height)
        .background(.thinMaterial)
        .onAppear {
            // Window is reused by SwiftUI — always restart from the beginning
            step = .welcome
            direction = 1
        }
    }

    // MARK: - Step content router

    @ViewBuilder
    private func stepView(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:       WelcomeStepView()
        case .services:      ServicesStepView()
        case .notifications: NotificationsStepView()
        case .widgets:       WidgetsStepView()
        case .done:          DoneStepView()
        }
    }

    // MARK: - Navigation bar

    private var navigationBar: some View {
        HStack {
            // Back button — invisible only on the first step
            Button(action: goBack) {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .opacity(step != .welcome ? 1 : 0)
            .disabled(step == .welcome)

            Spacer()

            // Progress dots
            progressDots

            Spacer()

            // Continue / Next button — invisible on Done step
            Button(action: goForward) {
                Text(step == .services ? "Continue" : "Next")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.brand)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance || step == .done)
            .opacity(step == .done ? 0 : 1)
        }
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s == step ? Color.brand : Color.secondary.opacity(0.25))
                    .frame(
                        width:  s == step ? 8 : 6,
                        height: s == step ? 8 : 6
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: step)
            }
        }
    }

    // MARK: - Transitions

    private var slideTransition: AnyTransition {
        direction > 0
            ? .asymmetric(
                insertion:  .move(edge: .trailing).combined(with: .opacity),
                removal:    .move(edge: .leading).combined(with: .opacity)
              )
            : .asymmetric(
                insertion:  .move(edge: .leading).combined(with: .opacity),
                removal:    .move(edge: .trailing).combined(with: .opacity)
              )
    }

    // MARK: - Navigation

    private var canAdvance: Bool {
        // Services step: require at least one authenticated service
        if step == .services {
            return viewModel.isCodexAuthenticated || viewModel.isClaudeAuthenticated
        }
        return true
    }

    private func goForward() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        direction = 1
        withAnimation { step = next }
    }

    private func goBack() {
        guard let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        direction = -1
        withAnimation { step = prev }
    }
}
