import Foundation
import Testing

@Suite("Popover typography")
struct PopoverTypographyTests {
    @Test("popover uses visibly larger font sizes for annotated small text")
    func popoverUsesLargerFontSizes() throws {
        let popoverSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/PopoverView.swift"), encoding: .utf8)
        let gaugeSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/CircularGaugeView.swift"), encoding: .utf8)

        #expect(popoverSource.contains(#"ringKey(label: "7d", opacity: 0.5)"#))
        #expect(popoverSource.contains(#"secondaryLabel: "7d""#))
        #expect(!popoverSource.contains(#"ringKey(label: "7-day", opacity: 0.5)"#))
        #expect(!popoverSource.contains(#"secondaryLabel: "7-day""#))

        #expect(popoverSource.contains(#".font(.system(size: 13, weight: .medium))"#))
        #expect(popoverSource.contains(#"Text(label + ":").font(.caption2).foregroundStyle(.secondary)"#))
        #expect(popoverSource.contains(#"Text(value).font(.caption2.monospacedDigit().bold())"#))
        #expect(!popoverSource.contains(#".font(.system(size: 13, weight: .bold).monospacedDigit())"#))

        #expect(gaugeSource.contains(#".font(.system(size: 13, weight: .medium))"#))
        #expect(gaugeSource.contains(#".font(.system(size: 13, weight: .semibold, design: .rounded))"#))
        #expect(gaugeSource.contains(#".font(.caption2.monospacedDigit())"#))
        #expect(gaugeSource.contains(".monospacedDigit()"))
        #expect(!gaugeSource.contains(#".font(.system(size: 12, weight: .semibold, design: .rounded))"#))
    }

    @Test("footer actions use padded labels for larger hit targets")
    func footerActionsUsePaddedLabels() throws {
        let popoverSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/PopoverView.swift"), encoding: .utf8)

        #expect(popoverSource.contains(#"footerActionLabel("Settings")"#))
        #expect(popoverSource.contains(#"footerActionLabel("Quit")"#))
        #expect(popoverSource.contains(#".padding(.horizontal, 12)"#))
        #expect(popoverSource.contains(#".padding(.vertical, 8)"#))
        #expect(popoverSource.contains(#".contentShape(Rectangle())"#))
    }

    @Test("secondary stat rows omit service-specific icons")
    func secondaryStatRowsOmitIcons() throws {
        let popoverSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/PopoverView.swift"), encoding: .utf8)

        // Credits row uses a dedicated text-first component, not a custom icon row.
        #expect(popoverSource.contains("CodexCreditsRow(balance: balance, autoReload: autoReload)"))
        #expect(popoverSource.contains("compactRow("))
        #expect(popoverSource.contains(#"private func compactRow(_ label: String, _ value: String, valueTint: Color = .primary, suffix: String? = nil) -> some View"#))
        #expect(!popoverSource.contains(#"Image(systemName: icon)"#))
        #expect(!popoverSource.contains(#"compactRow("Credits", "\(Int(balance))", "creditcard.fill")"#))
        #expect(!popoverSource.contains(#"compactRow("Extra", "\(Int(extra.usedCredits))/\(extra.monthlyLimit)", "plus.circle.fill")"#))
    }

    @Test("budget strips appear only for exception states")
    func budgetStripsAppearOnlyForExceptionStates() throws {
        let popoverSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/PopoverView.swift"), encoding: .utf8)
        let budgetStripSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/BudgetStripView.swift"), encoding: .utf8)
        let demoSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Demo/DemoDriver.swift"), encoding: .utf8)

        #expect(budgetStripSource.contains("static let showThreshold: Double = 100"))
        #expect(popoverSource.contains("if extra.utilization >= BudgetStripView.showThreshold"))
        #expect(popoverSource.contains("if utilization >= 95 { return .red }"))
        #expect(popoverSource.contains("if utilization >= 85 { return Color(red: 1.0, green: 0.65, blue: 0.0) }"))
        #expect(!popoverSource.contains("if utilization >= 70"))
        #expect(popoverSource.contains("isExhaustedWithoutReload && autoReload != nil"))
        #expect(popoverSource.contains("if shouldShowExceptionBar, let autoReload"))
        #expect(!popoverSource.contains("auto-reloads to"))
        #expect(demoSource.contains("map[24] = 0"))
        #expect(demoSource.contains("map[24] = off"))
        #expect(demoSource.contains("usedCredits: 2060, utilization: 103"))
    }

    @Test("reset lines use compact local-time captions")
    func resetLinesUseCompactCaptions() throws {
        let gaugeSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/CircularGaugeView.swift"), encoding: .utf8)
        let popoverSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/PopoverView.swift"), encoding: .utf8)

        // CircularGaugeView: date-based reset parameters exist
        #expect(gaugeSource.contains("resetAt: Date?"))
        #expect(gaugeSource.contains("weeklyResetAt: Date?"))

        // CircularGaugeView: captions use the compact formatter for popover density
        #expect(gaugeSource.contains("ResetTimeTextFormatter.compactWindowCaption(primaryLabel, resetAt: resetAt)"))
        #expect(gaugeSource.contains("ResetTimeTextFormatter.compactWindowCaption(secondaryLabel, resetAt: weeklyResetAt)"))
        #expect(gaugeSource.contains("Text(primaryCountdownText)"))
        #expect(gaugeSource.contains("Text(secondaryCountdownText)"))

        // PopoverView: Codex passes real weekly reset dates and exhaustion state
        #expect(popoverSource.contains("u.weeklyResetAt"))
        #expect(popoverSource.contains("u.isWeeklyExhausted"))

        // PopoverView: Claude passes real 7-day reset dates and exhaustion state
        #expect(popoverSource.contains("u.sevenDayResetsAt"))
        #expect(popoverSource.contains("u.sevenDayUtilization >= 100"))
    }

    @Test("7d reset line uses the inner-ring color treatment")
    func sevenDayResetLineMatchesInnerRingColor() throws {
        let gaugeSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/CircularGaugeView.swift"), encoding: .utf8)
        let widgetGaugeSource = try String(contentsOf: repoRoot.appending(path: "AIQuotaWidget/Views/WidgetGaugeView.swift"), encoding: .utf8)

        #expect(gaugeSource.contains("Circle()"))
        #expect(gaugeSource.contains(".stroke(statusColor.opacity(secondaryOpacity), style: StrokeStyle(lineWidth: innerLw, lineCap: .butt))"))
        #expect(gaugeSource.contains("AnyShapeStyle(statusColor.opacity(secondaryOpacity))"))

        #expect(widgetGaugeSource.contains("secondaryPercent >= 85 || secondaryLimitReached"))
        #expect(!widgetGaugeSource.contains("secondaryPercent >= 95 || secondaryLimitReached"))
        #expect(widgetGaugeSource.contains("CountdownTextFormatter.duration(weeklyResetSeconds, style: .compact)"))
    }

    private var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
