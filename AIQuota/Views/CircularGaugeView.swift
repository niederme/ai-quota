import SwiftUI

/// Dual-arc circular gauge — outer ring shows the primary window (5h),
/// inner ring shows the secondary window (7-day), like a watch complication.
struct CircularGaugeView: View {
    let primaryPercent: Int       // 5h window
    let primaryLimitReached: Bool
    let secondaryPercent: Int     // 7-day window
    let secondaryLimitReached: Bool
    let isLoading: Bool
    let icon: String              // asset image name
    let iconColor: Color
    let label: String
    let primaryWindowLabel: String   // e.g. "5h"
    let secondaryWindowLabel: String // e.g. "7-day"
    let resetSeconds: Int
    let isRefreshing: Bool
    let onRefresh: () -> Void

    /// Brand colour → amber when high → red at limit.
    private func ringColor(percent: Int, limitReached: Bool) -> Color {
        if limitReached || percent >= 95 { return .red }
        if percent >= 85 { return Color(red: 1.0, green: 0.65, blue: 0.0) } // amber
        return iconColor
    }

    private var primaryColor:   Color { ringColor(percent: primaryPercent,   limitReached: primaryLimitReached) }
    private var secondaryColor: Color { ringColor(percent: secondaryPercent, limitReached: secondaryLimitReached) }

    private var primaryFill:   Double { isLoading ? 0.5 : Double(max(0, min(100, primaryPercent)))   / 100.0 }
    private var secondaryFill: Double { isLoading ? 0.5 : Double(max(0, min(100, secondaryPercent))) / 100.0 }

    var body: some View {
        VStack(spacing: 8) {
            arcs
            caption
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Arcs

    private var arcs: some View {
        ZStack {
            // ── Outer ring: primary (5h) ──────────────────────────────
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: 0.75 * primaryFill)
                .stroke(primaryColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeInOut(duration: 0.5), value: primaryFill)

            // ── Inner ring: secondary (7-day) ─────────────────────────
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(20)

            Circle()
                .trim(from: 0, to: 0.75 * secondaryFill)
                .stroke(secondaryColor.opacity(0.75), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(20)
                .animation(.easeInOut(duration: 0.5), value: secondaryFill)

            // ── Centre: logo + primary % ──────────────────────────────
            VStack(spacing: 4) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(primaryLimitReached ? .red : iconColor)
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("\(primaryPercent)%")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(primaryColor)
                        .contentTransition(.numericText())
                        .animation(.default, value: primaryPercent)
                }
            }
        }
        .frame(width: 114, height: 114)
    }

    // MARK: - Caption

    private var caption: some View {
        VStack(spacing: 3) {
            // Service label + refresh
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(primaryLimitReached ? .red : .primary)
                if isRefreshing {
                    ProgressView().controlSize(.mini).scaleEffect(0.75)
                } else {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 9))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
                }
            }

            // Ring legend: ● 5h  ● 7-day
            HStack(spacing: 6) {
                ringLegend(primaryWindowLabel,   color: primaryColor)
                ringLegend(secondaryWindowLabel, color: secondaryColor.opacity(0.75))
            }

            // Reset countdown
            Text(primaryLimitReached ? "Limit reached · \(resetText)" : resetText)
                .font(.system(size: 9))
                .foregroundStyle(primaryLimitReached ? AnyShapeStyle(.red.opacity(0.8)) : AnyShapeStyle(.tertiary))
        }
    }

    private func ringLegend(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
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
