import SwiftUI

/// Dual-arc circular gauge — outer ring = primary window (5h),
/// inner ring = secondary window (7-day).
///
/// Both rings use the app's purple accent in the normal state,
/// shifting to amber at 85 % and red at the limit.
struct CircularGaugeView: View {

    // Shared accent — matches the app's Codex purple throughout.
    static let accent = Color(red: 0.62, green: 0.22, blue: 0.93)

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

    /// Single colour for both rings, driven by the worst status.
    private var statusColor: Color {
        if primaryLimitReached || secondaryLimitReached { return .red }
        let worst = max(primaryPercent, secondaryPercent)
        if worst >= 95 { return .red }
        if worst >= 85 { return Color(red: 1.0, green: 0.65, blue: 0.0) } // amber
        return Self.accent
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
    // Track: .round lineCap — rounded ends at the arc's 225° / 315° tips.
    // Fill:  .butt lineCap — flat ends, contained within the track footprint.

    private var arcs: some View {
        ZStack {
            // ── Outer track ───────────────────────────────────────────
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(135))

            // ── Outer fill (primary) ──────────────────────────────────
            Circle()
                .trim(from: 0, to: 0.75 * primaryFill)
                .stroke(statusColor, style: StrokeStyle(lineWidth: 9, lineCap: .butt))
                .rotationEffect(.degrees(135))
                .animation(.easeInOut(duration: 0.5), value: primaryFill)

            // ── Inner track (touching, no gap) ────────────────────────
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(8)

            // ── Inner fill (secondary) ────────────────────────────────
            Circle()
                .trim(from: 0, to: 0.75 * secondaryFill)
                .stroke(statusColor.opacity(0.5), style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                .rotationEffect(.degrees(135))
                .padding(8)
                .animation(.easeInOut(duration: 0.5), value: secondaryFill)

            // ── Centre: logo + labelled percentages ───────────────────
            VStack(spacing: 6) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.secondary)

                if isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    VStack(spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(primaryPercent)%")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(statusColor)
                                .contentTransition(.numericText())
                            Text(primaryLabel)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(secondaryPercent)%")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(statusColor.opacity(0.5))
                                .contentTransition(.numericText())
                            Text(secondaryLabel)
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
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
                    .font(.subheadline.bold())
                    .foregroundStyle(primaryLimitReached ? .red : .primary)
                if isRefreshing {
                    ProgressView().controlSize(.mini).scaleEffect(0.75)
                } else {
                    RefreshButton(action: onRefresh)
                }
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

// MARK: - Refresh button

/// A small refresh icon that highlights on hover and changes the cursor
/// to a pointing hand — making it feel interactive and easy to click.
private struct RefreshButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isHovering ? .primary : .tertiary)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isHovering ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
