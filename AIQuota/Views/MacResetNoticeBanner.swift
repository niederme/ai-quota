import SwiftUI

/// Mac-sized presentation of the iOS reset notice's two-line copy and link.
struct MacResetNoticeBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let onReadMore: () -> Void
    let onDismiss: () -> Void

    // Match the OverviewAccent and OverviewPrimary assets in iOS 2.0 (80).
    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 0.749020, green: 0.352941, blue: 0.949020)
            : Color(red: 0.686275, green: 0.321569, blue: 0.870588)
    }
    private var primary: Color {
        colorScheme == .dark ? .white : Color(red: 0.043137, green: 0.023529, blue: 0.058824)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onReadMore) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(primary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Read more on Codex Resets")
                        Image(systemName: "arrow.up.right")
                            .accessibilityHidden(true)
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(title). Read more on Codex Resets")

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor).opacity(0.75))
                    .frame(width: 32, height: 32, alignment: .topTrailing)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss reset announcement")
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
