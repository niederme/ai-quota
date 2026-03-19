import SwiftUI

/// Dual-arc circular gauge — outer ring = primary window (5h),
/// inner ring = secondary window (7-day). Both rings share a single
/// status-based colour: neutral → amber at 85% → red at limit.
struct CircularGaugeView: View {
    let primaryPercent: Int
    let primaryLimitReached: Bool
    let secondaryPercent: Int
    let secondaryLimitReached: Bool
    let isLoading: Bool
    let icon: String           // xcassets image name
    let label: String
    let primaryLabel: String   // e.g. "5h"
    let secondaryLabel: String // e.g. "7-day"
    let resetSeconds: Int
    let isRefreshing: Bool
    let onRefresh: () -> Void

    /// Single colour applied to both rings — driven by the worst status.
    private var statusColor: Color {
        if primaryLimitReached || secondaryLimitReached { return .red }
        let worst = max(primaryPercent, secondaryPercent)
        if worst >= 95 { return .red }
        if worst >= 85 { return Color(red: 1.0, green: 0.65, blue: 0.0) } // amber
        return .primary
    }

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
            // ── Outer track (primary) ─────────────────────────────────
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: 0.75 * primaryFill)
                .stroke(statusColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeInOut(duration: 0.5), value: primaryFill)

            // ── Inner track (secondary) — touching, no gap ────────────
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(8)

            Circle()
                .trim(from: 0, to: 0.75 * secondaryFill)
                .stroke(statusColor.opacity(0.55), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(8)
                .animation(.easeInOut(duration: 0.5), value: secondaryFill)

            // ── Centre: logo + both percentages ──────────────────────
            VStack(spacing: 1) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(.secondary)
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("\(primaryPercent)%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor)
                        .contentTransition(.numericText())
                        .animation(.default, value: primaryPercent)
                    Text("\(secondaryPercent)%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(statusColor.opacity(0.55))
                        .contentTransition(.numericText())
                        .animation(.default, value: secondaryPercent)
                }
            }
        }
        .frame(width: 114, height: 114)
    }

    // MARK: - Caption

    private var caption: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.footnote.bold())
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

            HStack(spacing: 5) {
                Text(primaryLabel).font(.system(size: 9)).foregroundStyle(.secondary)
                Text("·").font(.system(size: 9)).foregroundStyle(.quaternary)
                Text(secondaryLabel).font(.system(size: 9)).foregroundStyle(.secondary).opacity(0.65)
            }

            Text(primaryLimitReached ? "Limit reached · \(resetText)" : resetText)
                .font(.system(size: 9))
                .foregroundStyle(primaryLimitReached ? AnyShapeStyle(.red.opacity(0.8)) : AnyShapeStyle(.tertiary))
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
