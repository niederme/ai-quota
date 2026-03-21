// AIQuota/Views/Onboarding/Steps/WelcomeStepView.swift
import SwiftUI
import AppKit

struct WelcomeStepView: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: Color.brand.opacity(0.35), radius: 24, y: 8)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)

            Spacer().frame(height: 24)

            // App name — SF Rounded Display
            Text("AIQuota")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

            Spacer().frame(height: 12)

            // Tagline
            Text("Know your limits.\nKeep your flow.")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
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
