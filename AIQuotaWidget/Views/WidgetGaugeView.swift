import SwiftUI
import AIQuotaKit

/// Non-interactive dual-arc gauge for widget use.
/// Matches the visual language of the popover's CircularGaugeView —
/// outer ring = primary window (5h), inner ring = secondary window (7-day).
struct WidgetGaugeView: View {

    static let accent = Color(red: 0.62, green: 0.22, blue: 0.93)

    let primaryPercent: Int
    let primaryLimitReached: Bool
    let secondaryPercent: Int
    let icon: String        // xcassets image name (SVG)
    let label: String
    let primaryLabel: String   // e.g. "5h"
    let secondaryLabel: String // e.g. "7-day"
    let resetSeconds: Int
    let size: CGFloat

    private var statusColor: Color {
        if primaryLimitReached { return .red }
        let worst = max(primaryPercent, secondaryPercent)
        if worst >= 95 { return .red }
        if worst >= 85 { return Color(red: 1.0, green: 0.65, blue: 0.0) }
        return Self.accent
    }

    private var primaryFill:   Double { Double(max(0, min(100, primaryPercent)))   / 100.0 }
    private var secondaryFill: Double { Double(max(0, min(100, secondaryPercent))) / 100.0 }
    private var secondaryOpacity: Double {
        max(primaryPercent, secondaryPercent) >= 85 ? 0.65 : 0.45
    }

    // Scaled dimensions
    private var outerLW: CGFloat { size * 0.08 }
    private var innerLW: CGFloat { size * 0.08 }  // equal width
    private var innerPad: CGFloat { outerLW }      // touching rings
    private var iconPt:   CGFloat { size * 0.16 }
    private var primPt:   CGFloat { size * 0.175 }
    private var secPt:    CGFloat { size * 0.125 }
    private var labelPt:  CGFloat { size * 0.125 }
    private var resetPt:  CGFloat { size * 0.100 }

    var body: some View {
        VStack(spacing: size * 0.04) {
            ZStack {
                // ── Outer track ───────────────────────────────────────
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: outerLW, lineCap: .butt))
                    .rotationEffect(.degrees(135))

                Circle()
                    .trim(from: 0, to: 0.75 * primaryFill)
                    .stroke(statusColor, style: StrokeStyle(lineWidth: outerLW, lineCap: .butt))
                    .rotationEffect(.degrees(135))

                // ── Inner track (touching) ────────────────────────────
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: innerLW, lineCap: .butt))
                    .rotationEffect(.degrees(135))
                    .padding(innerPad)

                Circle()
                    .trim(from: 0, to: 0.75 * secondaryFill)
                    .stroke(statusColor.opacity(secondaryOpacity), style: StrokeStyle(lineWidth: innerLW, lineCap: .butt))
                    .rotationEffect(.degrees(135))
                    .padding(innerPad)

                // ── Centre ────────────────────────────────────────────
                VStack(spacing: size * 0.04) {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconPt, height: iconPt)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(primaryPercent)%")
                                .font(.system(size: primPt, weight: .bold, design: .rounded))
                                .foregroundStyle(statusColor)
                            Text(primaryLabel)
                                .font(.system(size: primPt * 0.58))
                                .foregroundStyle(.secondary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(secondaryPercent)%")
                                .font(.system(size: secPt, weight: .semibold, design: .rounded))
                                .foregroundStyle(statusColor.opacity(secondaryOpacity))
                            Text(secondaryLabel)
                                .font(.system(size: secPt * 0.7))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(width: size, height: size)

            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: labelPt, weight: .bold))
                    .foregroundStyle(primaryLimitReached ? .red : .primary)
                Text(resetText)
                    .font(.system(size: resetPt))
                    .foregroundStyle(.tertiary)
                Button(intent: RefreshWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: resetPt, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(3)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(.fill.tertiary)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .multilineTextAlignment(.center)
    }

    private var resetText: String {
        let days    = resetSeconds / 86400
        let hours   = (resetSeconds % 86400) / 3600
        let minutes = (resetSeconds % 3600) / 60
        if days > 0  { return "Resets \(days)d \(hours)h" }
        if hours > 0 { return "Resets \(hours)h \(minutes)m" }
        return "Resets \(minutes)m"
    }
}
