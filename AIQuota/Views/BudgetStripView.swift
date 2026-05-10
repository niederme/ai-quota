import SwiftUI
import AIQuotaKit

struct BudgetStripView: View {
    let extra: ClaudeUsage.ExtraUsage

    static let showThreshold: Double = 70

    private var color: Color {
        extra.utilization >= 85 ? .red : .orange
    }

    private var fraction: Double {
        min(max(extra.utilization / 100.0, 0), 1)
    }

    /// Abbreviates large limits to "2k" etc. to keep the footer line short.
    private var usedText: String {
        let used = Int(extra.usedCredits)
        let limit = extra.monthlyLimit >= 1000
            ? "\(extra.monthlyLimit / 1000)k"
            : "\(extra.monthlyLimit)"
        return "\(used) / \(limit)"
    }

    private var resetText: String {
        let cal = Calendar.current
        guard
            let nextMonth = cal.date(byAdding: .month, value: 1, to: .now),
            let first = cal.date(from: cal.dateComponents([.year, .month], from: nextMonth))
        else { return "monthly" }
        return "resets " + first.formatted(.dateTime.month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("Extra:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(usedText)
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Text("\(Int(extra.utilization.rounded()))%")
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.fill.quaternary)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 3)

            Text(resetText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        Divider()
        BudgetStripView(extra: .init(isEnabled: true, monthlyLimit: 2000, usedCredits: 1609, utilization: 80.45))
            .frame(width: 170)
        Divider()
        BudgetStripView(extra: .init(isEnabled: true, monthlyLimit: 2000, usedCredits: 1780, utilization: 89))
            .frame(width: 170)
    }
    .frame(width: 170)
    .background(.black.opacity(0.85))
}
