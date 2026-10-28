import SwiftUI

/// The iOS overview's account dial, sized for a Mac account row.
struct MacAccountDial: View {
    /// The 10pt outer stroke extends beyond the dial's nominal layout frame.
    static let strokeOutset: CGFloat = 5

    let icon: String
    let primaryPercent: Int?
    let primaryLabel: String
    let secondaryPercent: Int?
    let loading: Bool
    let connected: Bool
    let hasIssue: Bool
    var showsSecondaryPlaceholder = true

    private var tint: Color {
        guard connected else { return .overviewTertiary }
        let worst = max(primaryPercent ?? 0, secondaryPercent ?? 0)
        if worst >= 95 { return .overviewCritical }
        if worst >= 85 { return .overviewWarning }
        return .overviewAccent
    }

    private var showsSecondary: Bool { secondaryPercent != nil || (primaryPercent == nil && showsSecondaryPlaceholder) }

    var body: some View {
        ZStack {
            arc(percent: primaryPercent, lineWidth: showsSecondary ? 7 : 10, opacity: 1)
            if showsSecondary {
                arc(percent: secondaryPercent, lineWidth: 7, opacity: 0.7)
                    .padding(9)
            }
            VStack(spacing: 5) {
                Image(icon).resizable().scaledToFit().frame(width: 18, height: 18)
                if let primaryPercent {
                    VStack(spacing: 2) {
                        Text("\(primaryPercent)% \(primaryLabel)")
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if let secondaryPercent {
                            Text("\(secondaryPercent)% 7d")
                                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .opacity(0.7)
                        }
                    }
                } else {
                    VStack(spacing: 2) {
                        Text("— \(primaryLabel)")
                        if showsSecondary { Text("— 7d").opacity(0.7) }
                    }
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                }
            }
            .frame(width: 80)
            // Lift the second readout clear of the inner arc's open ends.
            .offset(y: showsSecondary ? -5 : 0)
            .foregroundStyle(tint)
        }
        .frame(width: 108, height: 108)
        // Include the outer stroke at the top, but don't reserve the circle's
        // unused lower quarter below the open arc.
        .padding(.top, Self.strokeOutset)
        .frame(height: 103, alignment: .top)
        .accessibilityHidden(true)
    }

    private func arc(percent: Int?, lineWidth: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(Color.overviewTrack, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt,
                                                           dash: []))
            if connected, let percent {
                Circle().trim(from: 0, to: 0.75 * Double(max(0, min(100, percent))) / 100)
                    .stroke(tint.opacity(opacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
        }
        .rotationEffect(.degrees(135))
    }
}
