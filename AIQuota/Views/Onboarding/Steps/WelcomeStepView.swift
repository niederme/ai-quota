// AIQuota/Views/Onboarding/Steps/WelcomeStepView.swift
import SwiftUI

struct WelcomeStepView: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo placeholder — replace with Image("AppLogo") when asset is ready
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.brand.opacity(0.85), Color.brand],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.brand.opacity(0.4), radius: 20, y: 6)

                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(.white)
            }
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)

            Spacer().frame(height: 28)

            // App name
            Text("AIQuota")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

            Spacer().frame(height: 10)

            // Tagline placeholder — update when final copy is decided
            Text("Keep an eye on your AI limits,\nright from the menu bar.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)

            Spacer()
        }
        .padding(.horizontal, 40)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.1)) {
                appeared = true
            }
        }
    }
}
