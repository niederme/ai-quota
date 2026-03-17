import SwiftUI
import AIQuotaKit

struct MenuBarIconView: View {
    let usage: CodexUsage?
    let isLoading: Bool

    private var pct: Int { usage?.weeklyUsedPercent ?? 0 }

    private var tintColor: Color {
        guard let usage else { return .secondary }
        if usage.limitReached { return .red }
        switch usage.weeklyUsedPercent {
        case ..<60: return .green
        case ..<85: return .yellow
        default: return .red
        }
    }

    private var symbolName: String {
        if isLoading { return "arrow.clockwise" }
        guard let usage else { return "brain.fill" }
        if usage.limitReached { return "exclamationmark.octagon.fill" }
        switch usage.weeklyUsedPercent {
        case ..<85: return "brain.fill"
        default: return "exclamationmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbolName)
                .foregroundStyle(tintColor)
                .symbolEffect(.rotate, isActive: isLoading)
            if usage != nil {
                Text("\(pct)%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .contentTransition(.numericText())
            }
        }
    }
}
