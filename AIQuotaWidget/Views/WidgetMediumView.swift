import SwiftUI
import AIQuotaKit

private let widgetAccentColor = Color(red: 0.62, green: 0.22, blue: 0.93)

private struct WidgetDetailRowData: Identifiable {
    let label: String
    let value: String
    let icon: String
    let tint: Color

    var id: String { "\(label)-\(value)-\(icon)" }
}

private struct WidgetServiceSnapshot {
    let label: String
    let icon: String
    let primaryPercent: Int
    let primaryLimitReached: Bool
    let secondaryPercent: Int
    let resetSeconds: Int
    let weeklyResetSeconds: Int
    let secondaryLimitReached: Bool
    let detailRows: [WidgetDetailRowData]
    let detailFooter: String
    let alertText: String?

    var statusColor: Color {
        if primaryLimitReached || secondaryLimitReached { return .red }
        let worst = max(primaryPercent, secondaryPercent)
        if worst >= 95 { return .red }
        if worst >= 85 { return Color(red: 1.0, green: 0.65, blue: 0.0) }
        return widgetAccentColor
    }
}

private extension QuotaEntry {
    func snapshot(for service: ServiceType) -> WidgetServiceSnapshot? {
        switch service {
        case .codex:
            guard let usage = codexUsage else { return nil }
            var detailRows = [
                WidgetDetailRowData(
                    label: "Remaining",
                    value: "\(usage.weeklyRemaining)%",
                    icon: "sparkles",
                    tint: usage.limitReached ? .red : widgetAccentColor
                ),
                WidgetDetailRowData(
                    label: "Plan",
                    value: usage.planType.capitalized,
                    icon: "person.fill",
                    tint: .secondary
                ),
            ]
            if let balance = usage.creditBalance {
                detailRows.append(
                    WidgetDetailRowData(
                        label: "Credits",
                        value: "\(Int(balance))",
                        icon: "creditcard.fill",
                        tint: .secondary
                    )
                )
            }
            return WidgetServiceSnapshot(
                label: "Codex",
                icon: "logo-openai",
                primaryPercent: usage.hourlyUsedPercent,
                primaryLimitReached: usage.hourlyUsedPercent >= 100,
                secondaryPercent: usage.weeklyUsedPercent,
                resetSeconds: usage.hourlyResetAfterSeconds,
                weeklyResetSeconds: usage.weeklyResetAfterSeconds,
                secondaryLimitReached: usage.isWeeklyExhausted,
                detailRows: detailRows,
                detailFooter: widgetCountdownText(prefix: "7d resets", seconds: usage.weeklyResetAfterSeconds),
                alertText: usage.limitReached ? "Limit reached" : nil
            )

        case .claude:
            guard let usage = claudeUsage else { return nil }
            var detailRows = [
                WidgetDetailRowData(
                    label: "Remaining",
                    value: "\(usage.remainingPercent)%",
                    icon: "sparkles",
                    tint: usage.limitReached ? .red : widgetAccentColor
                ),
                WidgetDetailRowData(
                    label: "Plan",
                    value: usage.planDisplayName,
                    icon: "person.fill",
                    tint: .secondary
                ),
            ]
            if let extra = usage.extraUsage, extra.isEnabled {
                detailRows.append(
                    WidgetDetailRowData(
                        label: "Extra",
                        value: "\(Int(extra.usedCredits))/\(extra.monthlyLimit)",
                        icon: "plus.circle.fill",
                        tint: .secondary
                    )
                )
            }
            return WidgetServiceSnapshot(
                label: "Claude Code",
                icon: "logo-claude",
                primaryPercent: usage.usedPercent,
                primaryLimitReached: usage.limitReached,
                secondaryPercent: Int(usage.sevenDayUtilization.rounded()),
                resetSeconds: usage.resetAfterSeconds,
                weeklyResetSeconds: usage.sevenDayResetAfterSeconds,
                secondaryLimitReached: usage.sevenDayUtilization >= 100,
                detailRows: detailRows,
                detailFooter: widgetCountdownText(prefix: "7d resets", seconds: usage.sevenDayResetAfterSeconds),
                alertText: usage.limitReached ? "Limit reached" : nil
            )
        }
    }
}

private func widgetCountdownText(prefix: String, seconds: Int) -> String {
    let days = seconds / 86400
    let hours = (seconds % 86400) / 3600
    let minutes = (seconds % 3600) / 60
    if days > 0 { return "\(prefix) \(days)d \(hours)h" }
    if hours > 0 { return "\(prefix) \(hours)h \(minutes)m" }
    return "\(prefix) \(minutes)m"
}

private struct WidgetHeaderView: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(widgetAccentColor.opacity(0.18))
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(widgetAccentColor)
                    .frame(width: 5, height: 5)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            ringKey(label: "5h", opacity: 1.0)
            ringKey(label: "7d", opacity: 0.5)
        }
    }

    private func ringKey(label: String, opacity: Double) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(widgetAccentColor.opacity(opacity))
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(widgetAccentColor.opacity(opacity))
        }
    }
}

private struct WidgetStatsColumn: View {
    let snapshot: WidgetServiceSnapshot?
    let emptyLabel: String
    let showsFooter: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let snapshot {
                if let alertText = snapshot.alertText {
                    Label(alertText, systemImage: "exclamationmark.octagon.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.bottom, 3)
                }

                ForEach(snapshot.detailRows) { row in
                    HStack(spacing: 5) {
                        Image(systemName: row.icon)
                            .font(.system(size: 9))
                            .foregroundStyle(row.tint)
                            .frame(width: 13)
                        Text(row.label + ":")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(row.value)
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                if showsFooter {
                    Text(snapshot.detailFooter)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            } else {
                Text("Sign in to AIQuota")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("Connect \(emptyLabel) in the menu bar app.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WidgetMediumStatsColumn: View {
    let snapshot: WidgetServiceSnapshot?
    let emptyLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot {
                if let alertText = snapshot.alertText {
                    Label(alertText, systemImage: "exclamationmark.octagon.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }

                ForEach(snapshot.detailRows) { row in
                    HStack(spacing: 5) {
                        Image(systemName: row.icon)
                            .font(.system(size: 9))
                            .foregroundStyle(row.tint)
                            .frame(width: 13)
                        Text(row.label + ":")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(row.value)
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Text(snapshot.detailFooter)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 4)

                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text("Sign in to AIQuota")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("Connect \(emptyLabel) in the menu bar app.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct WidgetSingleGaugePanel: View {
    let snapshot: WidgetServiceSnapshot?
    let service: ServiceType
    let gaugeSize: CGFloat

    var body: some View {
        Group {
            if let snapshot {
                WidgetGaugeView(
                    primaryPercent: snapshot.primaryPercent,
                    primaryLimitReached: snapshot.primaryLimitReached,
                    secondaryPercent: snapshot.secondaryPercent,
                    icon: snapshot.icon,
                    label: snapshot.label,
                    primaryLabel: "5h",
                    secondaryLabel: "7-day",
                    resetSeconds: snapshot.resetSeconds,
                    weeklyResetSeconds: snapshot.weeklyResetSeconds,
                    secondaryLimitReached: snapshot.secondaryLimitReached,
                    size: gaugeSize
                )
            } else {
                WidgetEmptyGaugeView(
                    icon: service == .claude ? "logo-claude" : "logo-openai",
                    label: service == .claude ? "Claude Code" : "Codex",
                    size: gaugeSize
                )
            }
        }
    }
}

private struct WidgetEmptyGaugeView: View {
    let icon: String
    let label: String
    let size: CGFloat

    var body: some View {
        VStack(spacing: size * 0.04) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .butt))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .butt))
                    .rotationEffect(.degrees(135))
                    .padding(size * 0.08)
                VStack(spacing: 4) {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.16, height: size * 0.16)
                        .foregroundStyle(widgetAccentColor.opacity(0.35))
                    Text("—")
                        .font(.system(size: size * 0.17, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: size, height: size)

            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: size * 0.125, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("Not connected")
                    .font(.system(size: size * 0.1, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .multilineTextAlignment(.center)
    }
}

private struct WidgetServiceDetailPanel: View {
    let snapshot: WidgetServiceSnapshot
    let gaugeSize: CGFloat
    let detailSpacing: CGFloat

    var body: some View {
        HStack(spacing: 14) {
            WidgetGaugeView(
                primaryPercent: snapshot.primaryPercent,
                primaryLimitReached: snapshot.primaryLimitReached,
                secondaryPercent: snapshot.secondaryPercent,
                icon: snapshot.icon,
                label: snapshot.label,
                primaryLabel: "5h",
                secondaryLabel: "7-day",
                resetSeconds: snapshot.resetSeconds,
                weeklyResetSeconds: snapshot.weeklyResetSeconds,
                secondaryLimitReached: snapshot.secondaryLimitReached,
                size: gaugeSize
            )
            .frame(width: gaugeSize + 18)

            VStack(alignment: .leading, spacing: detailSpacing) {
                if let alertText = snapshot.alertText {
                    Label(alertText, systemImage: "exclamationmark.octagon.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }

                ForEach(snapshot.detailRows) { row in
                    HStack(spacing: 5) {
                        Image(systemName: row.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(row.tint)
                            .frame(width: 14)
                        Text(row.label + ":")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(row.value)
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer(minLength: 0)

                Text(snapshot.detailFooter)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WidgetEmptyDetailPanel: View {
    let icon: String
    let label: String
    let gaugeSize: CGFloat

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(widgetAccentColor.opacity(0.3))
                Text("—")
                    .font(.title.bold())
                    .foregroundStyle(.tertiary)
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(width: gaugeSize + 18)

            VStack(alignment: .leading, spacing: 5) {
                Text("Not connected")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("Sign in to AIQuota to load this service in the widget.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WidgetSingleServiceMediumView: View {
    let entry: QuotaEntry

    private var service: ServiceType {
        entry.configuration.service == .claude ? .claude : .codex
    }

    var body: some View {
        let snapshot = entry.snapshot(for: service)

        HStack(spacing: 0) {
            WidgetSingleGaugePanel(snapshot: snapshot, service: service, gaugeSize: 88)
                .frame(width: 128)

            Divider()
                .padding(.vertical, 22)

            WidgetMediumStatsColumn(
                snapshot: snapshot,
                emptyLabel: service == .claude ? "Claude Code" : "Codex"
            )
            .padding(.leading, 18)
            .padding(.trailing, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WidgetMediumView: View {
    let entry: QuotaEntry

    var body: some View {
        Group {
            // Exactly one service enrolled → centered single gauge.
            // Zero (never enrolled / after reset) or two → dual layout.
            if entry.enrolledServices.count == 1 {
                singleLayout
            } else {
                dualLayout
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dualLayout: some View {
        HStack(spacing: 0) {
            gaugeSlot(for: .codex, size: 80).frame(maxWidth: .infinity)
            Divider().padding(.vertical, 12)
            gaugeSlot(for: .claude, size: 80).frame(maxWidth: .infinity)
        }
    }

    private var singleLayout: some View {
        // `enrolledServices.count == 1` is guaranteed at call site
        let service = entry.enrolledServices.first ?? .codex
        return gaugeSlot(for: service, size: 90)
    }

    // MARK: - Gauge slot

    @ViewBuilder
    private func gaugeSlot(for service: ServiceType, size: CGFloat) -> some View {
        switch service {
        case .codex:
            if let u = entry.codexUsage {
                WidgetGaugeView(
                    primaryPercent: u.hourlyUsedPercent,
                    primaryLimitReached: u.hourlyUsedPercent >= 100,
                    secondaryPercent: u.weeklyUsedPercent,
                    icon: "logo-openai",
                    label: "Codex",
                    primaryLabel: "5h",
                    secondaryLabel: "7-day",
                    resetSeconds: u.hourlyResetAfterSeconds,
                    weeklyResetSeconds: u.weeklyResetAfterSeconds,
                    secondaryLimitReached: u.isWeeklyExhausted,
                    size: size
                )
            } else {
                emptySlot(icon: "logo-openai", label: "Codex")
            }

        case .claude:
            if let u = entry.claudeUsage {
                WidgetGaugeView(
                    primaryPercent: u.usedPercent,
                    primaryLimitReached: u.limitReached,
                    secondaryPercent: Int(u.sevenDayUtilization.rounded()),
                    icon: "logo-claude",
                    label: "Claude Code",
                    primaryLabel: "5h",
                    secondaryLabel: "7-day",
                    resetSeconds: u.resetAfterSeconds,
                    weeklyResetSeconds: u.sevenDayResetAfterSeconds,
                    secondaryLimitReached: u.sevenDayUtilization >= 100,
                    size: size
                )
            } else {
                emptySlot(icon: "logo-claude", label: "Claude Code")
            }
        }
    }

    private func emptySlot(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundStyle(WidgetGaugeView.accent.opacity(0.3))
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            Text("Sign in to AIQuota").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}

struct WidgetLargeView: View {
    let entry: QuotaEntry

    var body: some View {
        VStack(spacing: 0) {
            WidgetHeaderView(title: "AIQuota")
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            Divider()

            GeometryReader { geometry in
                let topHeight = geometry.size.height * 0.64
                let bottomHeight = max(0, geometry.size.height - topHeight - 1)

                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 0) {
                        largeGaugeColumn(for: .codex)
                            .frame(maxWidth: .infinity)
                        Divider()
                        largeGaugeColumn(for: .claude)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: topHeight, alignment: .center)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    Divider()

                    HStack(alignment: .top, spacing: 0) {
                        WidgetStatsColumn(
                            snapshot: entry.snapshot(for: .codex),
                            emptyLabel: "Codex",
                            showsFooter: false
                        )
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        WidgetStatsColumn(
                            snapshot: entry.snapshot(for: .claude),
                            emptyLabel: "Claude Code",
                            showsFooter: false
                        )
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: bottomHeight, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func largeGaugeColumn(for service: ServiceType) -> some View {
        WidgetSingleGaugePanel(snapshot: entry.snapshot(for: service), service: service, gaugeSize: 96)
    }
}
