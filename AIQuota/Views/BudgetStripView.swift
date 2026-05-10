import SwiftUI
import AIQuotaKit

struct BudgetStripView: View {
    let extra: ClaudeUsage.ExtraUsage

    static let showThreshold: Double = 100

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
        guard let nextMonth = cal.date(byAdding: .month, value: 1, to: .now) else {
            return "monthly"
        }
        let month = cal.component(.month, from: nextMonth)
        return "resets \(Self.nytMonth(month)) 1"
    }

    /// NYT style: short months get periods (Jan., Feb., Aug., Sept., Oct., Nov., Dec.);
    /// March, April, May, June, July are written out in full.
    private static func nytMonth(_ month: Int) -> String {
        switch month {
        case 1:  return "Jan."
        case 2:  return "Feb."
        case 3:  return "March"
        case 4:  return "April"
        case 5:  return "May"
        case 6:  return "June"
        case 7:  return "July"
        case 8:  return "Aug."
        case 9:  return "Sept."
        case 10: return "Oct."
        case 11: return "Nov."
        case 12: return "Dec."
        default: return ""
        }
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
        BudgetStripView(extra: .init(isEnabled: true, monthlyLimit: 2000, usedCredits: 2000, utilization: 100))
            .frame(width: 170)
        Divider()
        BudgetStripView(extra: .init(isEnabled: true, monthlyLimit: 2000, usedCredits: 2060, utilization: 103))
            .frame(width: 170)
    }
    .frame(width: 170)
    .background(.black.opacity(0.85))
}
