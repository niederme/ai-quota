import SwiftUI
import AIQuotaKit

struct WidgetSmallView: View {
    let entry: QuotaEntry

    private var showClaude: Bool {
        entry.configuration.service == .claude
    }

    private var pct: Int {
        showClaude ? (entry.claudeUsage?.usedPercent ?? 0)
                   : (entry.codexUsage?.weeklyUsedPercent ?? 0)
    }

    private var limitReached: Bool {
        showClaude ? (entry.claudeUsage?.limitReached ?? false)
                   : (entry.codexUsage?.limitReached ?? false)
    }

    private var tintColor: Color {
        if limitReached { return .red }
        switch pct {
        case ..<60: return .green
        case ..<85: return .yellow
        default:    return .red
        }
    }

    private var serviceName: String { showClaude ? "Claude Code" : "Codex" }
    private var serviceIcon: String { limitReached ? "exclamationmark.octagon.fill"
                                                   : (showClaude ? "sparkles" : "brain.fill") }
    private var serviceColor: Color { showClaude ? Color(red: 0.8, green: 0.45, blue: 0.1) : .purple }

    private var hasData: Bool {
        showClaude ? entry.claudeUsage != nil : entry.codexUsage != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Label(serviceName, systemImage: serviceIcon)
                .font(.caption2.bold())
                .foregroundStyle(limitReached ? .red : serviceColor)

            Spacer()

            if hasData {
                VStack(spacing: 4) {
                    Image(nsImage: GaugeImageMaker.image(
                        usedPercent: pct,
                        limitReached: limitReached,
                        isLoading: false,
                        size: 40
                    ))
                    .frame(width: 40, height: 40)

                    Text("\(pct)%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .foregroundStyle(tintColor)
                }

                Spacer()

                VStack(spacing: 2) {
                    if limitReached {
                        Text("Limit reached")
                            .font(.caption2.bold())
                            .foregroundStyle(.red)
                    } else {
                        if showClaude, let u = entry.claudeUsage {
                            Text("\(u.remainingPercent)% remaining")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if let u = entry.codexUsage {
                            Text("\(u.weeklyRemaining)% remaining")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(countdownText())
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("—").font(.title.bold()).foregroundStyle(.tertiary)
                Spacer()
                Text("Sign in to AIQuota")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func countdownText() -> String {
        let seconds: Int
        if showClaude {
            seconds = entry.claudeUsage?.resetAfterSeconds ?? 0
        } else {
            seconds = entry.codexUsage?.weeklyResetAfterSeconds ?? 0
        }
        let days  = seconds / 86400
        let hours = (seconds % 86400) / 3600
        if days > 0 { return "Resets \(days)d \(hours)h" }
        return "Resets \(hours)h \((seconds % 3600) / 60)m"
    }
}
