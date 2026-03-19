import SwiftUI

/// A circular arc gauge used as the primary visual in the popover.
///
/// Renders a 270° arc track with a colour-coded fill that animates as
/// the percentage changes. The service icon and percentage sit in the centre;
/// the service label, window label, and reset countdown appear below.
struct CircularGaugeView: View {
    let percent: Int
    let limitReached: Bool
    let isLoading: Bool
    let icon: String
    let iconColor: Color
    let label: String
    let windowLabel: String
    let resetSeconds: Int
    let isRefreshing: Bool
    let onRefresh: () -> Void

    private var tintColor: Color {
        if limitReached { return .red }
        switch percent {
        case ..<60: return .green
        case ..<85: return .yellow
        default:    return .red
        }
    }

    private var fillFraction: Double {
        isLoading ? 0.5 : Double(max(0, min(100, percent))) / 100.0
    }

    var body: some View {
        VStack(spacing: 8) {
            arc
            caption
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Arc

    private var arc: some View {
        ZStack {
            // Track (full 270° arc)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Fill arc
            Circle()
                .trim(from: 0, to: 0.75 * fillFraction)
                .stroke(tintColor, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeInOut(duration: 0.5), value: fillFraction)

            // Centre: icon + percent
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(limitReached ? .red : iconColor)
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("\(percent)%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(tintColor)
                        .contentTransition(.numericText())
                        .animation(.default, value: percent)
                }
            }
        }
        .frame(width: 100, height: 100)
    }

    // MARK: - Caption

    private var caption: some View {
        VStack(spacing: 3) {
            // Label + refresh button
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(limitReached ? .red : .primary)
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

            Text(windowLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text(limitReached ? "Limit reached · \(resetText)" : resetText)
                .font(.system(size: 9))
                .foregroundStyle(limitReached ? AnyShapeStyle(.red.opacity(0.8)) : AnyShapeStyle(.tertiary))
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
