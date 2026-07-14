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
        #expect(popoverSource.contains(#"Text(label + ":").font(.caption2).foregroundStyle(labelTint)"#))
        // Stats row values are intentionally NOT bold — the reset captions with their
        // urgency color carry the real signal, and bolding metadata inverted the hierarchy.
        #expect(popoverSource.contains(#"Text(value).font(.caption2.monospacedDigit())"#))
        #expect(!popoverSource.contains(#"Text(value).font(.caption2.monospacedDigit().bold())"#))
        #expect(!popoverSource.contains(#".font(.system(size: 13, weight: .bold).monospacedDigit())"#))

        #expect(gaugeSource.contains(#".font(.system(size: 13, weight: .medium))"#))
        #expect(gaugeSource.contains(#".font(.system(size: 13, weight: .semibold, design: .rounded))"#))
        #expect(gaugeSource.contains(#".font(.caption2.monospacedDigit())"#))
        #expect(gaugeSource.contains(#"Text(label)"#))
        #expect(gaugeSource.contains(#".foregroundStyle(.foreground)"#))
        #expect(!gaugeSource.contains(#".foregroundStyle(.primary)"#))
        #expect(!gaugeSource.contains(#".foregroundStyle(.white)"#))
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
        #expect(popoverSource.contains(#"labelTint: Color = .secondary"#))
        #expect(popoverSource.contains(#"valueTint: Color = .primary"#))
        #expect(!popoverSource.contains(#"Image(systemName: icon)"#))
        #expect(!popoverSource.contains(#"compactRow("Credits", "\(Int(balance))", "creditcard.fill")"#))
        #expect(!popoverSource.contains(#"compactRow("Spent", "\(Int(extra.usedCredits))/\(extra.monthlyLimit)", "plus.circle.fill")"#))
    }

    @Test("budget strips appear only for exception states")
    func budgetStripsAppearOnlyForExceptionStates() throws {
        let popoverSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/PopoverView.swift"), encoding: .utf8)
        let budgetStripSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/BudgetStripView.swift"), encoding: .utf8)
        let demoSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Demo/DemoDriver.swift"), encoding: .utf8)

        #expect(budgetStripSource.contains("static let showThreshold: Double = 100"))
        #expect(popoverSource.contains("if extra.utilization >= BudgetStripView.showThreshold"))
        #expect(budgetStripSource.contains(#"Text("Spent:")"#))
        #expect(budgetStripSource.contains("extra.utilization >= 85 ? .critical : .warningAmber"))
        #expect(popoverSource.contains("private func extraUsageValueTint(_ extra: ClaudeUsage.ExtraUsage) -> Color?"))
        #expect(popoverSource.contains("guard extra.utilization >= 85 else { return nil }"))
        #expect(popoverSource.contains("valueTint: tint"))
        #expect(!popoverSource.contains("if utilization >= 70"))
        #expect(popoverSource.contains("isExhaustedWithoutReload && autoReload != nil"))
        #expect(popoverSource.contains("if shouldShowExceptionBar, let autoReload"))
        #expect(!popoverSource.contains("auto-reloads to"))
        #expect(demoSource.contains("map[20] = 0"))
        #expect(demoSource.contains("map[20] = off"))
        #expect(demoSource.contains("map[22] = 238"))
        #expect(demoSource.contains("map[24] = extra(5150)"))
    }

    @Test("duplicate network errors collapse into one banner")
    func duplicateNetworkErrorsCollapseIntoOneBanner() throws {
        let popoverSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/PopoverView.swift"), encoding: .utf8)

        #expect(popoverSource.contains(#"id: "network""#))
        #expect(popoverSource.contains(#"message: "No network connection. Showing cached data.""#))
        #expect(popoverSource.contains("viewModel.codexError?.isNetworkUnavailable == true"))
        #expect(popoverSource.contains("viewModel.claudeError?.isNetworkUnavailable == true"))
        #expect(popoverSource.contains(#"message: "\(serviceName): \(banner.message)""#))
        #expect(popoverSource.contains("let shouldPrefixService = viewModel.isCodexEnrolled && viewModel.isClaudeEnrolled"))
    }

    @Test("Sequoia popover uses a controlled adaptive surface")
    func sequoiaPopoverUsesControlledSurface() throws {
        let popoverSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/PopoverView.swift"), encoding: .utf8)

        #expect(popoverSource.contains("if #available(macOS 26.0, *)"))
        #expect(popoverSource.contains(".fill(.regularMaterial)"))
        #expect(!popoverSource.contains("Color.black.opacity(0.26)"))
        #expect(popoverSource.contains("Color(nsColor: .windowBackgroundColor).opacity(0.92)"))
    }

    @Test("accent text uses adaptive colors without shadows")
    func accentTextUsesAdaptiveColorsWithoutShadows() throws {
        let gaugeSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/CircularGaugeView.swift"), encoding: .utf8)
        let popoverSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/PopoverView.swift"), encoding: .utf8)
        let colorsSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/AdaptiveColors.swift"), encoding: .utf8)

        #expect(colorsSource.contains(#"static let brand = Color("BrandAccent")"#))
        #expect(colorsSource.contains(#"static let gaugeAccent = Color(nsColor: .systemPurple)"#))
        #expect(colorsSource.contains(#"static let warningAmber = Color(nsColor: .systemOrange)"#))
        #expect(colorsSource.contains(#"static let critical = Color(nsColor: .systemRed)"#))
        #expect(gaugeSource.contains("static let accent = Color.gaugeAccent"))
        #expect(gaugeSource.contains("private var secondaryTextOpacity"))
        #expect(gaugeSource.contains("return .warningAmber"))
        #expect(popoverSource.contains("private static let amber = Color.warningAmber"))
        #expect(!gaugeSource.contains("accentLegibilityLift"))
        #expect(!popoverSource.contains("accentLegibilityLift"))
        #expect(!gaugeSource.contains(".shadow("))
        #expect(!popoverSource.contains(".shadow("))
    }

    @Test("gauge empty tracks use tertiary fill")
    func gaugeEmptyTracksUseTertiaryFill() throws {
        let gaugeSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/CircularGaugeView.swift"), encoding: .utf8)
        let popoverSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/PopoverView.swift"), encoding: .utf8)

        #expect(gaugeSource.components(separatedBy: ".stroke(.fill.tertiary").count == 3)
        #expect(popoverSource.components(separatedBy: ".stroke(.fill.tertiary").count == 3)
        #expect(!gaugeSource.contains(".stroke(.fill.quaternary"))
        #expect(!popoverSource.contains(".stroke(.fill.quaternary"))
    }

    @Test("onboarding reinforces material only before Tahoe")
    func onboardingMatchesPopoverSurface() throws {
        let onboardingSource = try String(
            contentsOf: repoRoot.appending(path: "AIQuota/Views/Onboarding/OnboardingView.swift"),
            encoding: .utf8
        )

        #expect(onboardingSource.contains("Rectangle()"))
        #expect(onboardingSource.contains(".fill(.regularMaterial)"))
        #expect(onboardingSource.contains("if #available(macOS 26.0, *)"))
        #expect(onboardingSource.contains("Color(nsColor: .windowBackgroundColor).opacity(0.92)"))
        #expect(onboardingSource.contains("onboardingSurface\n                .ignoresSafeArea()"))
        #expect(!onboardingSource.contains("Color.black.opacity(0.18)"))
    }

    @Test("dark widget surface uses dark semantic foregrounds")
    func darkWidgetSurfaceUsesDarkSemanticForegrounds() throws {
        let widgetSource = try String(contentsOf: repoRoot.appending(path: "AIQuotaWidget/AIQuotaWidget.swift"), encoding: .utf8)

        #expect(widgetSource.components(separatedBy: #".environment(\.colorScheme, .dark)"#).count == 3)
        #expect(widgetSource.components(separatedBy: #"containerBackground(Color(white: 0.1), for: .widget)"#).count == 3)
    }

    @Test("reset lines use compact local-time captions")
    func resetLinesUseCompactCaptions() throws {
        let gaugeSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/CircularGaugeView.swift"), encoding: .utf8)
        let popoverSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/PopoverView.swift"), encoding: .utf8)
        let notificationSource = try String(contentsOf: repoRoot.appending(path: "Packages/AIQuotaKit/Sources/AIQuotaKit/Notifications/NotificationManager.swift"), encoding: .utf8)
        let viewModelSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/ViewModels/QuotaViewModel.swift"), encoding: .utf8)

        // CircularGaugeView: date-based reset parameters exist
        #expect(gaugeSource.contains("resetAt: Date?"))
        #expect(gaugeSource.contains("weeklyResetAt: Date?"))
        #expect(gaugeSource.contains("showsSecondaryMetric: Bool"))
        #expect(gaugeSource.contains(#"Text("No \(primaryLabel) limit right now")"#))

        // CircularGaugeView: captions use the compact formatter for popover density
        #expect(gaugeSource.contains("ResetTimeTextFormatter.compactWindowCaption(primaryLabel, resetAt: resetAt)"))
        #expect(gaugeSource.contains("ResetTimeTextFormatter.compactWindowCaption(secondaryLabel, resetAt: weeklyResetAt)"))
        #expect(gaugeSource.contains("Text(primaryCountdownText)"))
        #expect(gaugeSource.contains("Text(secondaryCountdownText)"))

        // PopoverView: Codex passes real weekly reset dates and exhaustion state
        #expect(popoverSource.contains("u.weeklyResetAt"))
        #expect(popoverSource.contains("u.isWeeklyExhausted"))
        #expect(popoverSource.contains("showsPrimaryMetric: hasHourlyWindow"))
        #expect(popoverSource.contains("secondaryPercent: u.weeklyUsedPercent"))
        #expect(notificationSource.contains("if current.hasHourlyWindow"))
        #expect(notificationSource.contains("defaults.removeObject(forKey: Key.codex5hLastResetAt)"))
        #expect(viewModelSource.contains("codexUsage.hasHourlyWindow && codexUsage.hourlyResetAfterSeconds <= 900"))

        // PopoverView: Claude passes real 7-day reset dates and exhaustion state
        #expect(popoverSource.contains("u.sevenDayResetsAt"))
        #expect(popoverSource.contains("(u.sevenDayUtilization ?? 0) >= 100"))
    }

    @Test("reset lines use the gauge status color treatment")
    func resetLinesUseGaugeStatusColorTreatment() throws {
        let gaugeSource = try String(contentsOf: repoRoot.appending(path: "AIQuota/Views/CircularGaugeView.swift"), encoding: .utf8)
        let widgetGaugeSource = try String(contentsOf: repoRoot.appending(path: "AIQuotaWidget/Views/WidgetGaugeView.swift"), encoding: .utf8)

        #expect(gaugeSource.contains("Circle()"))
        #expect(gaugeSource.contains(".stroke(statusColor.opacity(secondaryOpacity), style: StrokeStyle(lineWidth: innerLw, lineCap: .butt))"))
        #expect(gaugeSource.contains("Text(primaryCountdownText)"))
        #expect(gaugeSource.contains("private var primaryCaptionStyle"))
        #expect(gaugeSource.contains(#"return AnyShapeStyle(Color.critical)"#))
        #expect(gaugeSource.contains(#"if worst >= 85 { return AnyShapeStyle(Color.warningAmber) }"#))
        #expect(gaugeSource.contains(#"return AnyShapeStyle(Self.accent.opacity(0.85))"#))
        #expect(gaugeSource.contains("Text(secondaryCountdownText)"))
        #expect(gaugeSource.contains("private var secondaryCaptionStyle"))
        #expect(gaugeSource.contains("AnyShapeStyle(statusColor.opacity(secondaryTextOpacity))"))
        #expect(!gaugeSource.contains(".red.opacity(0.8)"))

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
