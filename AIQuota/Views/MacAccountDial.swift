import SwiftUI

/// The iOS overview's account dial, sized for a Mac account row.
struct MacAccountDial: View {
    let icon: String
    let primaryPercent: Int?
    let primaryLabel: String
    let secondaryPercent: Int?
    let loading: Bool
    let connected: Bool
    let hasIssue: Bool

    private var tint: Color {
        guard connected, !hasIssue else { return .secondary }
        let worst = max(primaryPercent ?? 0, secondaryPercent ?? 0)
        if worst >= 95 { return .overviewCritical }
        if worst >= 85 { return .overviewWarning }
        return .overviewAccent
    }

    var body: some View {
        ZStack {
            arc(percent: primaryPercent, lineWidth: secondaryPercent == nil ? 12 : 8, opacity: 1)
            if secondaryPercent != nil {
                arc(percent: secondaryPercent, lineWidth: 8, opacity: 0.7)
                    .padding(10)
            }
            VStack(spacing: secondaryPercent == nil ? 2 : 5) {
                Image(icon).resizable().scaledToFit().frame(width: 18, height: 18)
                if loading && primaryPercent == nil {
                    ProgressView().controlSize(.mini)
                } else if let primaryPercent {
                    if let secondaryPercent {
                        VStack(spacing: 2) {
                            Text("\(primaryPercent)% \(primaryLabel)")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            Text("\(secondaryPercent)% 7d")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .opacity(0.7)
                        }
                    } else {
                        Text("\(primaryPercent)%")
                            .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        // The period label is the ring's key, so it keeps the ring colour.
                        Text(primaryLabel)
                            .font(.system(size: 10, weight: .medium))
                    }
                } else {
                    Text("—").font(.subheadline)
                }
            }
            .foregroundStyle(tint)
        }
        .frame(width: 120, height: 120)
        .accessibilityHidden(true)
    }

    private func arc(percent: Int?, lineWidth: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(Color(nsColor: .quaternaryLabelColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt,
                                                           dash: percent == nil && !loading ? [3, 4] : []))
            if connected, let percent {
                Circle().trim(from: 0, to: 0.75 * Double(max(0, min(100, percent))) / 100)
                    .stroke(tint.opacity(opacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
        }
        .rotationEffect(.degrees(135))
    }
}
