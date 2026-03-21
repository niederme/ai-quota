// AIQuota/Views/Onboarding/Steps/DoneStepView.swift
import SwiftUI

struct DoneStepView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated checkmark
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 90, height: 90)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.green)
                    .scaleEffect(appeared ? 1 : 0.5)
                    .opacity(appeared ? 1 : 0)
            }

            Spacer().frame(height: 24)

            Text("You're all set!")
                .font(.title).fontWeight(.bold)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

            Spacer().frame(height: 32)

            // CTA button
            Button(action: finish) {
                Text("Start using AIQuota")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color.brand)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(appeared ? 1 : 0)

            Spacer()

            // Footer — identical to Settings about block
            VStack(spacing: 3) {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
                Text("AIQuota \(version) (\(build))")
                    .fontWeight(.medium)
                Text("Made by John Niedermeyer, with a little help from\nClaude, Codex and friends.")
                    .multilineTextAlignment(.center)
                Text("Need Help?")
                    .padding(.top, 4)
                HStack(spacing: 12) {
                    Link("GitHub Issues", destination: URL(string: "https://github.com/niederme/ai-quota/issues")!)
                        .foregroundColor(Color.brand)
                    Text("·").foregroundStyle(.quaternary)
                    Link("@niederme on X", destination: URL(string: "https://x.com/niederme")!)
                        .foregroundColor(Color.brand)
                }
            }
            .font(.callout)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.bottom, 24)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
        }
    }

    private func finish() {
        viewModel.completeOnboarding()
        dismissWindow(id: "onboarding")
    }
}
