import SwiftUI

struct AnalyticsConsentCard: View {
    @Binding var isEnabled: Bool

    private let privacyPolicyURL = URL(string: "https://aiquota.app/privacy/")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Text("Share anonymous usage data")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                Toggle("Share anonymous usage data", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Share anonymous usage data")
            }

            Text("Share app launches, active use, setup completion, and app version. No prompts, tokens, cookies, or personal info.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text("Off by default. Change anytime in Settings.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                Link(destination: privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "lock.shield")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color.brand)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
