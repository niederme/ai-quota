import SwiftUI
import AIQuotaKit

struct CountdownView: View {
    let resetAt: Date?

    @State private var now = Date.now
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var text: String {
        guard let resetAt else { return "Reset time unavailable" }
        if resetAt < now { return "Resetting now…" }
        let seconds = Int(resetAt.timeIntervalSince(now))
        return "Resets in \(CountdownTextFormatter.duration(seconds))"
    }

    private var absoluteText: String {
        guard let resetAt else { return "" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: resetAt)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(.caption.weight(.medium))
                if !absoluteText.isEmpty {
                    Text(absoluteText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onReceive(timer) { _ in now = Date.now }
    }
}
