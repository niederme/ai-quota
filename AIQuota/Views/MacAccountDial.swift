import SwiftUI

/// Two-window readings use the iOS dial's compact value-and-period lines.
/// Keeping the Mac dial at 100 points protects the neighboring account text.
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
        if worst >= 95 { return .critical }
        if worst >= 85 { return .warningAmber }
        return .gaugeAccent
    }

    var body: some View {
        ZStack {
            arc(percent: primaryPercent, lineWidth: secondaryPercent == nil ? 11 : 8, opacity: 1)
            if secondaryPercent != nil {
                arc(percent: secondaryPercent, lineWidth: 7, opacity: 0.65)
                    .padding(10)
            }
            VStack(spacing: secondaryPercent == nil ? 2 : 5) {
                Image(icon).resizable().scaledToFit().frame(width: 16, height: 16)
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
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
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
        .frame(width: 100, height: 100)
        .accessibilityHidden(true)
    }

    private func arc(percent: Int?, lineWidth: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(.fill.tertiary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt,
                                                           dash: percent == nil && !loading ? [3, 4] : []))
            if connected && !loading, let percent {
                Circle().trim(from: 0, to: 0.75 * Double(max(0, min(100, percent))) / 100)
                    .stroke(tint.opacity(opacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
        }
        .rotationEffect(.degrees(135))
    }
}
