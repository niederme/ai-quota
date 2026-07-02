import SwiftUI
import AIQuotaKit

/// Dual-arc circular gauge — outer ring = primary window (5h),
/// inner ring = secondary window (7-day).
///
/// Both rings use the app's purple accent in the normal state,
/// shifting to amber at 85 % and red at the limit.
struct CircularGaugeView: View {

    // Shared accent — macOS resolves system purple for the current appearance.
    static let accent = Color.gaugeAccent

    let primaryPercent: Int
    let primaryLimitReached: Bool
    let secondaryPercent: Int
    let secondaryLimitReached: Bool
    let isLoading: Bool
    let icon: String           // xcassets image name
    let label: String
    let primaryLabel: String   // e.g. "5h"
    let secondaryLabel: String // e.g. "7-day"
    let resetAt: Date?
    let weeklyResetAt: Date?
    let isRefreshing: Bool
    let onRefresh: () -> Void

    /// Single colour for both rings, driven by the worst status.
    private var statusColor: Color {
        if primaryLimitReached || secondaryLimitReached { return .critical }
        let worst = max(primaryPercent, secondaryPercent)
        if worst >= 95 { return .critical }
        if worst >= 85 { return .warningAmber }
        return Self.accent
    }

    private var primaryFill:   Double { Double(max(0, min(100, primaryPercent))) / 100.0 }
    private var secondaryFill: Double { Double(max(0, min(100, secondaryPercent))) / 100.0 }
    /// Inner ring is always subordinate — same hue, lower opacity.
    private var secondaryOpacity: Double {
        let worst = max(primaryPercent, secondaryPercent)
        return worst >= 85 ? 0.65 : 0.45
    }

    private var secondaryTextOpacity: Double {
        let worst = max(primaryPercent, secondaryPercent)
        return worst >= 85 ? 0.75 : 0.65
    }

    /// Reset captions echo the gauge state so the timing metadata stays tied to
    /// the quota signal without relying on shadows or custom background tricks.
    private var primaryCaptionStyle: AnyShapeStyle {
        let worst = max(primaryPercent, secondaryPercent)
        if primaryLimitReached || secondaryLimitReached || worst >= 95 {
            return AnyShapeStyle(Color.critical)
        }
        if worst >= 85 { return AnyShapeStyle(Color.warningAmber) }
        return AnyShapeStyle(Self.accent.opacity(0.85))
    }

    private var secondaryCaptionStyle: AnyShapeStyle {
        AnyShapeStyle(statusColor.opacity(secondaryTextOpacity))
    }

    // Outer ring is slightly wider than inner (9pt vs 7pt), with a 2pt optical gap.
    // innerPad = outerLw/2 + 2 + innerLw/2 = 4.5 + 2 + 3.5 = 10
    private let outerLw: CGFloat = 9
    private let innerLw: CGFloat = 7
    private var innerPad: CGFloat { outerLw / 2 + 2 + innerLw / 2 }

    var body: some View {
        VStack(spacing: 4) {
            arcs
            caption
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Arcs
    // All strokes use .butt lineCap — flat ends at the arc's open tips.
    // Rounded caps on tracks create visible bubbles at the 225°/315° endpoints.

    private var arcs: some View {
        ZStack {
            // ── Outer track ───────────────────────────────────────────
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.fill.tertiary, style: StrokeStyle(lineWidth: outerLw, lineCap: .butt))
                .rotationEffect(.degrees(135))

            // ── Outer fill (primary) ──────────────────────────────────
            Circle()
                .trim(from: 0, to: 0.75 * primaryFill)
                .stroke(statusColor, style: StrokeStyle(lineWidth: outerLw, lineCap: .butt))
                .rotationEffect(.degrees(135))
                .animation(.easeInOut(duration: 0.5), value: primaryFill)

            // ── Inner track (7pt, 2pt gap from outer) ─────────────────
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.fill.tertiary, style: StrokeStyle(lineWidth: innerLw, lineCap: .butt))
                .rotationEffect(.degrees(135))
                .padding(innerPad)

            // ── Inner fill (secondary) ────────────────────────────────
            Circle()
                .trim(from: 0, to: 0.75 * secondaryFill)
                .stroke(statusColor.opacity(secondaryOpacity), style: StrokeStyle(lineWidth: innerLw, lineCap: .butt))
                .rotationEffect(.degrees(135))
                .padding(innerPad)
                .animation(.easeInOut(duration: 0.5), value: secondaryFill)

            // ── Centre: logo + labelled percentages ───────────────────
            VStack(spacing: 6) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(statusColor)

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
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(statusColor)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(secondaryPercent)%")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(statusColor.opacity(secondaryTextOpacity))
                                .contentTransition(.numericText())
                            Text(secondaryLabel)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(statusColor.opacity(secondaryTextOpacity))
                        }
                    }
                }
            }

            // ── Refresh button — sits in the arc's bottom gap ─────────
            VStack {
                Spacer()
                ZStack {
                    RefreshButton(action: onRefresh)
                        .opacity(isRefreshing ? 0 : 1)
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.8)
                        .opacity(isRefreshing ? 1 : 0)
                }
                .animation(.easeInOut(duration: 0.15), value: isRefreshing)
                .padding(.bottom, 2)
                .offset(y: 3)
            }
        }
        .frame(width: 114, height: 114)
    }

    // MARK: - Caption

    private var caption: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.headline.bold())
                .foregroundStyle(.foreground)

            VStack(spacing: 0) {
                Text(primaryCountdownText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(primaryCaptionStyle)

                if !isLoading {
                    Text(secondaryCountdownText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(secondaryCaptionStyle)
                }
            }
        }
    }

    private var primaryCountdownText: String {
        ResetTimeTextFormatter.compactWindowCaption(primaryLabel, resetAt: resetAt)
    }

    private var secondaryCountdownText: String {
        ResetTimeTextFormatter.compactWindowCaption(secondaryLabel, resetAt: weeklyResetAt)
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
