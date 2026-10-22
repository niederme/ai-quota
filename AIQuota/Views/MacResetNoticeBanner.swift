import SwiftUI

/// The same reset notice adapts to the compact and multi-account panel widths.
struct MacResetNoticeBanner: View {
    let title: String
    let width: CGFloat
    let accent: Color
    let onReadMore: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onReadMore) {
                VStack(alignment: .leading, spacing: 5) {
                    // The one-account panel is 340pt; wider constrained panels
                    // can place the link icon beside the title without crowding it.
                    if width >= 420 {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            noticeTitle
                            Spacer(minLength: 8)
                            linkIcon
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    } else {
                        noticeTitle
                        linkIcon
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(title). Read more on Codex Resets")

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss reset announcement")
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var noticeTitle: some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var linkIcon: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(accent)
            .frame(width: 24, height: 24, alignment: .leading)
            .accessibilityHidden(true)
    }
}
