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
        #expect(gaugeSource.contains(#".font(.system(size: 11, weight: .medium))"#))
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

        #expect(popoverSource.contains(#"compactRow("Credits", "\(Int(balance))")"#))
        #expect(popoverSource.contains(#"compactRow("Extra", "\(Int(extra.usedCredits))/\(extra.monthlyLimit)")"#))
        #expect(popoverSource.contains(#"private func compactRow(_ label: String, _ value: String) -> some View"#))
        #expect(!popoverSource.contains(#"Image(systemName: icon)"#))
        #expect(!popoverSource.contains(#"compactRow("Credits", "\(Int(balance))", "creditcard.fill")"#))
        #expect(!popoverSource.contains(#"compactRow("Extra", "\(Int(extra.usedCredits))/\(extra.monthlyLimit)", "plus.circle.fill")"#))
    }

    @Test("7d reset line appears in gauge caption when 7d is critical")
    func sevenDayResetLineInCaption() throws {
        let gaugeSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/CircularGaugeView.swift"), encoding: .utf8)
        let popoverSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/PopoverView.swift"), encoding: .utf8)

        // CircularGaugeView: new parameter exists
        #expect(gaugeSource.contains("weeklyResetSeconds: Int"))

        // CircularGaugeView: weeklyResetText produces full "7d Resets …" strings
        #expect(gaugeSource.contains(#""7d Resets \(days)d \(hours)h""#))
        #expect(gaugeSource.contains(#""7d Resets \(hours)h \(minutes)m""#))
        #expect(gaugeSource.contains(#""7d Resets \(minutes)m""#))

        // CircularGaugeView: 7d limit reached state
        #expect(gaugeSource.contains(#""7d limit reached · \(weeklyResetText)""#))

        // PopoverView: Codex passes real weekly reset seconds and exhaustion state
        #expect(popoverSource.contains("u.weeklyResetAfterSeconds"))
        #expect(popoverSource.contains("u.isWeeklyExhausted"))

        // PopoverView: Claude passes real 7-day reset seconds and exhaustion state
        #expect(popoverSource.contains("u.sevenDayResetAfterSeconds"))
        #expect(popoverSource.contains("u.sevenDayUtilization >= 100"))
    }

    @Test("7d reset line appears when 7d enters the amber warning band")
    func sevenDayResetLineUsesAmberThreshold() throws {
        let gaugeSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/CircularGaugeView.swift"), encoding: .utf8)
        let widgetGaugeSource = try String(contentsOf: repoRoot.appending(path: "AIQuotaWidget/Views/WidgetGaugeView.swift"), encoding: .utf8)

        #expect(gaugeSource.contains("secondaryPercent >= 85 || secondaryLimitReached"))
        #expect(!gaugeSource.contains("secondaryPercent >= 95 || secondaryLimitReached"))

        #expect(widgetGaugeSource.contains("secondaryPercent >= 85 || secondaryLimitReached"))
        #expect(!widgetGaugeSource.contains("secondaryPercent >= 95 || secondaryLimitReached"))
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
