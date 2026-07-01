import SwiftUI
import AIQuotaKit

struct PopoverView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.openSettings) private var openSettings

    /// Captured reference to the MenuBarExtra NSWindow so we can re-show it
    /// after Settings opens (which steals key focus and causes the window to close).
    @State private var menuBarWindow: NSWindow?

    private var popoverWidth: CGFloat {
        viewModel.enrolledServices.count == 1 ? 240 : 340
    }

    var body: some View {
        Group {
            if viewModel.isRestoringSession {
                restoringSessionContent
            } else if !viewModel.enrolledServices.isEmpty {
                authenticatedContent
            } else {
                signInContent
            }
        }
        .frame(width: popoverWidth)
        .background { popoverSurface }
        .background(WindowCapture { menuBarWindow = $0 })
        .background {
            Button("") { viewModel.manualRefresh() }
                .keyboardShortcut("r", modifiers: .command)
                .hidden()
        }
    }

    @ViewBuilder
    private var popoverSurface: some View {
        if #available(macOS 26.0, *) {
            Color.black.opacity(0.26)
        } else {
            // Sequoia's MenuBarExtra material is substantially more transparent
            // than Tahoe's glass treatment. Stabilize contrast while retaining a
            // small amount of desktop color.
            Color(nsColor: .windowBackgroundColor).opacity(0.92)
        }
    }

    // MARK: - Restoring session

    private var restoringSessionContent: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Restoring session…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: popoverWidth, height: 120)
    }

    private func openSettingsKeepingPopover() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.async { menuBarWindow?.orderFront(nil) }
    }

    // MARK: - Authenticated layout

    @ViewBuilder
    private var authenticatedContent: some View {
        VStack(spacing: 0) {
            header

            ForEach(errorBanners) { banner in
                errorBanner(banner)
                Divider()
            }

            gaugeRow
                .padding(.top, 16).padding(.bottom, 10)

            statsRow

            Divider()
            footer
        }
    }

    // MARK: - Gauge slots

    @ViewBuilder
    private var codexGaugeSlot: some View {
        if viewModel.isCodexAuthenticated {
            if let u = viewModel.codexUsage {
                CircularGaugeView(
                    primaryPercent: u.hourlyUsedPercent,
                    primaryLimitReached: u.hourlyUsedPercent >= 100,
                    secondaryPercent: u.weeklyUsedPercent,
                    secondaryLimitReached: u.isWeeklyExhausted,
                    isLoading: false,
                    icon: "logo-openai",
                    label: "Codex",
                    primaryLabel: formatWindowDuration(u.hourlyWindowSeconds),
                    secondaryLabel: "7d",
                    resetAt: u.hourlyResetAt == .distantFuture ? nil : u.hourlyResetAt,
                    weeklyResetAt: u.weeklyResetAt == .distantFuture ? nil : u.weeklyResetAt,
                    isRefreshing: viewModel.isCodexLoading,
                    onRefresh: { viewModel.manualRefresh() }
                )
                .help(codexTooltip(u))
            } else {
                CircularGaugeView(
                    primaryPercent: 0, primaryLimitReached: false,
                    secondaryPercent: 0, secondaryLimitReached: false,
                    isLoading: true, icon: "logo-openai",
                    label: "Codex", primaryLabel: "5h", secondaryLabel: "7d",
                    resetAt: nil, weeklyResetAt: nil, isRefreshing: true, onRefresh: {}
                )
            }
        } else {
            connectGauge(icon: "logo-openai", label: "Codex") {
                Task { await viewModel.signIn() }
            }
        }
    }

    @ViewBuilder
    private var claudeGaugeSlot: some View {
        if viewModel.isClaudeAuthenticated {
            if let u = viewModel.claudeUsage {
                CircularGaugeView(
                    primaryPercent: u.usedPercent,
                    primaryLimitReached: u.limitReached,
                    secondaryPercent: Int(u.sevenDayUtilization?.rounded() ?? 0),
                    secondaryLimitReached: (u.sevenDayUtilization ?? 0) >= 100,
                    isLoading: false,
                    icon: "logo-claude",
                    label: "Claude Code",
                    primaryLabel: u.primaryMetricLabel,
                    secondaryLabel: "7d",
                    resetAt: u.resetAt,
                    weeklyResetAt: u.sevenDayResetsAt,
                    isRefreshing: viewModel.isClaudeLoading,
                    onRefresh: { viewModel.manualRefresh() }
                )
                .help(claudeTooltip(u))
            } else {
                CircularGaugeView(
                    primaryPercent: 0, primaryLimitReached: false,
                    secondaryPercent: 0, secondaryLimitReached: false,
                    isLoading: true, icon: "logo-claude",
                    label: "Claude Code", primaryLabel: "5h", secondaryLabel: "7d",
                    resetAt: nil, weeklyResetAt: nil, isRefreshing: true, onRefresh: {}
                )
            }
        } else {
            connectGauge(icon: "logo-claude", label: "Claude Code") {
                Task { await viewModel.signInClaude() }
            }
        }
    }

    @ViewBuilder
    private var gaugeRow: some View {
        if viewModel.isCodexEnrolled && viewModel.isClaudeEnrolled {
            HStack(alignment: .top, spacing: 0) {
                codexGaugeSlot.frame(maxWidth: .infinity)
                Divider()
                claudeGaugeSlot.frame(maxWidth: .infinity)
            }
        } else if viewModel.isCodexEnrolled {
            codexGaugeSlot
        } else {
            claudeGaugeSlot
        }
    }

    @ViewBuilder
    private var statsRow: some View {
        let bothEnrolled = viewModel.isCodexEnrolled && viewModel.isClaudeEnrolled
        let hasCodexStats = viewModel.isCodexEnrolled && viewModel.codexUsage != nil
        let hasClaudeStats = viewModel.isClaudeEnrolled && viewModel.claudeUsage != nil

        if hasCodexStats || hasClaudeStats {
            Divider()
            if bothEnrolled && hasCodexStats && hasClaudeStats {
                HStack(alignment: .top, spacing: 0) {
                    codexSecondaryStats
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    claudeSecondaryStats
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 7)
            } else if hasCodexStats {
                codexSecondaryStats
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                claudeSecondaryStats
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func codexTooltip(_ u: CodexUsage) -> String {
        var lines = [
            "\(formatWindowDuration(u.hourlyWindowSeconds)) window: \(u.hourlyUsedPercent)% used",
            "7-day window: \(u.weeklyUsedPercent)% used",
        ]
        if let balance = u.creditBalance { lines.append("Credits balance: \(formatCodexDollarAmount(balance))") }
        if let spent = u.bonusCreditsSpentThisMonth {
            lines.append("Usage credits spent this month: \(formatCodexDollarAmount(spent))")
        }
        if let local = u.approxLocalMessages, local.count == 2 {
            lines.append("Local messages: ~\(local[0]) / \(local[1])")
        }
        if let cloud = u.approxCloudMessages, cloud.count == 2 {
            lines.append("Cloud messages: ~\(cloud[0]) / \(cloud[1])")
        }
        lines.append("Plan: \(u.planType.capitalized)")
        return lines.joined(separator: "\n")
    }

    private func claudeTooltip(_ u: ClaudeUsage) -> String {
        var lines = [
            "\(u.primaryMetricLabel) usage: \(u.primaryMetric.utilization.map { "\(Int($0.rounded()))% used" } ?? "unknown")",
        ]
        if let sevenDay = u.sevenDayUtilization {
            lines.append("7-day window: \(Int(sevenDay.rounded()))% used")
        }
        if let bonus = u.bonusUsage {
            lines.append("Spent this month: \(formatBonusSpend(bonus))")
        }
        if let extra = u.extraUsage, extra.isEnabled {
            lines.append("Monthly limit: \(Int(extra.usedCredits)) / \(extra.monthlyLimit)")
        }
        if let spend = u.spendLimit {
            lines.append("Spend limit: \(Int(spend.used)) / \(Int(spend.limit))")
        }
        lines.append("Plan: \(u.planDisplayName)")
        return lines.joined(separator: "\n")
    }

    private func connectGauge(icon: String, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.fill.quaternary, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                    .rotationEffect(.degrees(135))
                    .padding(8)
                VStack(spacing: 2) {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(CircularGaugeView.accent.opacity(0.35))
                    Text("—")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.quaternary)
                }
                VStack {
                    Spacer()
                    Button("Connect", action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.bottom, 2)
                }
            }
            .frame(width: 114, height: 114)

            VStack(spacing: 2) {
                Text(label)
                    .font(.headline.bold())
                Text("Not connected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Secondary stats

    @ViewBuilder
    private var codexSecondaryStats: some View {
        if let usage = viewModel.codexUsage {
            let autoReload = viewModel.codexAutoReload
            VStack(alignment: .leading, spacing: 5) {
                compactRow("Plan", usage.planType.capitalized)
                if let balance = usage.creditBalance {
                    CodexCreditsRow(balance: balance, autoReload: autoReload)
                }
                if let spent = usage.bonusCreditsSpentThisMonth, spent > 0 {
                    compactRow(
                        "Spent",
                        formatCodexDollarAmount(spent),
                        labelTint: overageValueTint,
                        valueTint: overageValueTint,
                        infoHelp: codexSpentHelpText
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var claudeSecondaryStats: some View {
        if let usage = viewModel.claudeUsage {
            VStack(alignment: .leading, spacing: 6) {
                compactRow("Plan", usage.planDisplayName)
                if let extra = usage.extraUsage, extra.isEnabled {
                    if extra.utilization >= BudgetStripView.showThreshold {
                        BudgetStripView(extra: extra)
                    } else if let tint = extraUsageValueTint(extra) {
                        compactRow(
                            "Spent",
                            formatBonusSpend(usage.bonusUsage, fallback: extra.usedCredits),
                            labelTint: tint,
                            valueTint: tint,
                            infoHelp: claudeSpentHelpText
                        )
                    } else {
                        compactRow(
                            "Spent",
                            formatBonusSpend(usage.bonusUsage, fallback: extra.usedCredits),
                            labelTint: overageValueTint,
                            valueTint: overageValueTint,
                            infoHelp: claudeSpentHelpText
                        )
                    }
                } else if let bonus = usage.bonusUsage, bonus.spent > 0 {
                    compactRow(
                        "Spent",
                        formatBonusSpend(bonus),
                        labelTint: overageValueTint,
                        valueTint: overageValueTint,
                        infoHelp: claudeSpentHelpText
                    )
                }
            }
        }
    }

    private var overageValueTint: Color {
        Color(red: 1.0, green: 0.65, blue: 0.0)
    }

    /// Overage spend is amber. Red is reserved for the cap-hit strip.
    private func extraUsageValueTint(_ extra: ClaudeUsage.ExtraUsage) -> Color? {
        guard extra.utilization >= 85 else { return nil }
        return overageValueTint
    }

    private func compactRow(
        _ label: String,
        _ value: String,
        labelTint: Color = .secondary,
        valueTint: Color = .primary,
        suffix: String? = nil,
        infoHelp: String? = nil
    ) -> some View {
        CompactStatRow(
            label: label,
            value: value,
            labelTint: labelTint,
            valueTint: valueTint,
            suffix: suffix,
            infoHelp: infoHelp
        )
    }

    private var codexSpentHelpText: String {
        "Codex usage-credit events summed for \(currentMonthName). Converted at 25 credits = $1."
    }

    private var claudeSpentHelpText: String {
        "Claude reports this as monthly extra usage for \(currentMonthName). The response does not include an exact reset date."
    }

    private var currentMonthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: .now)
    }

    private func formatBonusSpend(_ bonus: ClaudeUsage.BonusUsage?, fallback: Double) -> String {
        guard let bonus else { return formatCreditAmount(fallback) }
        return formatBonusSpend(bonus)
    }

    private func formatBonusSpend(_ bonus: ClaudeUsage.BonusUsage) -> String {
        if let currencyCode = bonus.currencyCode {
            return formatCurrencyAmount(bonus.spent, currencyCode: currencyCode)
        }
        return formatCreditAmount(bonus.spent)
    }

    private func formatCurrencyAmount(_ amount: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currencyCode) \(formatCreditAmount(amount))"
    }

    private func formatCodexDollarAmount(_ credits: Double) -> String {
        formatCurrencyAmount(credits / 25.0, currencyCode: "USD")
    }

    private func formatCreditAmount(_ amount: Double) -> String {
        let absAmount = abs(amount)
        if absAmount >= 1_000 {
            return String(format: "%.1fk", amount / 1_000)
        }
        if absAmount >= 100 || amount.rounded() == amount {
            return "\(Int(amount.rounded()))"
        }
        let formatted = String(format: "%.1f", amount)
        return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 20, height: 20)
            Text("AIQuota").font(.headline)
            Spacer()
            // Colour key for the dual rings
            HStack(spacing: 12) {
                ringKey(label: "5h",    opacity: 1.0)
                ringKey(label: "7d", opacity: 0.5)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        Divider()
    }

    private func ringKey(label: String, opacity: Double) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(CircularGaugeView.accent.opacity(opacity))
                .frame(width: 6, height: 6)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CircularGaugeView.accent.opacity(opacity))
                .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        ZStack {
            HStack {
                Button { openSettingsKeepingPopover() } label: {
                    footerActionLabel("Settings")
                }
                Spacer()
                Button(role: .destructive) { NSApp.terminate(nil) } label: {
                    footerActionLabel("Quit")
                }
            }
            if let date = viewModel.lastRefreshedAt {
                TimelineView(.periodic(from: date, by: 60)) { _ in
                    Text(date.relativeFormatted)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Sign-In landing (both unauthenticated)

    private var signInContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 60, height: 60)
                VStack(spacing: 5) {
                    Text("AIQuota").font(.title3.bold())
                    Text("Monitor your AI quota at a glance.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 8) {
                    signInButton(
                        logo: "logo-openai",
                        label: "Sign in with ChatGPT",
                        action: { Task { await viewModel.signIn() } }
                    )
                    signInButton(
                        logo: "logo-claude",
                        label: "Sign in with Claude",
                        action: { Task { await viewModel.signInClaude() } }
                    )
                }
            }
            .padding(24)
            Divider()
            HStack {
                Button { openSettingsKeepingPopover() } label: {
                    footerActionLabel("Settings")
                }
                Spacer()
                Button(role: .destructive) { NSApp.terminate(nil) } label: {
                    footerActionLabel("Quit")
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func signInButton(logo: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text(label)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                // Invisible spacer to balance the logo and keep text visually centred
                Color.clear.frame(width: 16, height: 16)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private func footerActionLabel(_ title: String) -> some View {
        Text(title)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
    }

    // MARK: - Error Banner

    private struct ErrorBanner: Identifiable {
        let id: String
        let message: String
        let dismiss: () -> Void
        let retry: (() -> Void)?
        let signIn: (() -> Void)?
    }

    private var errorBanners: [ErrorBanner] {
        var banners: [ErrorBanner] = []

        if viewModel.isCodexEnrolled, let error = viewModel.codexError {
            banners.append(ErrorBanner(
                id: "codex",
                message: error.localizedDescription,
                dismiss: { viewModel.codexError = nil },
                retry: { viewModel.manualRefresh() },
                signIn: error.isAuthError ? { Task { await viewModel.signIn() } } : nil
            ))
        }

        if viewModel.isClaudeEnrolled, let error = viewModel.claudeError {
            banners.append(ErrorBanner(
                id: "claude",
                message: error.localizedDescription,
                dismiss: { viewModel.claudeError = nil },
                retry: { viewModel.manualRefresh() },
                signIn: error.isAuthError ? { Task { await viewModel.signInClaude() } } : nil
            ))
        }

        if viewModel.codexError?.isNetworkUnavailable == true,
           viewModel.claudeError?.isNetworkUnavailable == true,
           viewModel.isCodexEnrolled,
           viewModel.isClaudeEnrolled {
            return [
                ErrorBanner(
                    id: "network",
                    message: "No network connection. Showing cached data.",
                    dismiss: {
                        viewModel.codexError = nil
                        viewModel.claudeError = nil
                    },
                    retry: { viewModel.manualRefresh() },
                    signIn: nil
                )
            ]
        }

        let shouldPrefixService = viewModel.isCodexEnrolled && viewModel.isClaudeEnrolled
        guard shouldPrefixService else { return banners }

        return banners.map { banner in
            let serviceName = banner.id == "codex" ? "Codex" : "Claude Code"
            return ErrorBanner(
                id: banner.id,
                message: "\(serviceName): \(banner.message)",
                dismiss: banner.dismiss,
                retry: banner.retry,
                signIn: banner.signIn
            )
        }
    }

    private func errorBanner(_ banner: ErrorBanner) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.footnote)
            Text(banner.message)
                .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            if let signIn = banner.signIn {
                Button("Sign In", action: signIn)
                    .buttonStyle(.borderless)
                    .font(.footnote.bold())
                    .foregroundStyle(.orange)
            } else if let retry = banner.retry {
                Button {
                    retry()
                } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
                .buttonStyle(.borderless)
            }
            Button(action: banner.dismiss) {
                Image(systemName: "xmark").font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.orange.opacity(0.1))
    }

    // MARK: - Helpers

    private func formatWindowDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        return hours > 0 ? "\(hours)h" : "\(seconds / 60)m"
    }
}

private extension NetworkError {
    var isNetworkUnavailable: Bool {
        if case .networkUnavailable = self { return true }
        return false
    }
}

private struct CompactStatRow: View {
    let label: String
    let value: String
    let labelTint: Color
    let valueTint: Color
    let suffix: String?
    let infoHelp: String?

    @State private var isShowingInfo = false
    @State private var hoverDelayTask: Task<Void, Never>?

    var body: some View {
        if let infoHelp {
            Button {
                hoverDelayTask?.cancel()
                isShowingInfo = true
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover(perform: hoverChanged)
            .accessibilityLabel("\(label): \(value). \(infoHelp)")
            .onDisappear {
                hoverDelayTask?.cancel()
            }
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 5) {
            Text(label + ":").font(.caption2).foregroundStyle(labelTint)
            valueLabel
            if let suffix {
                Text(suffix).font(.caption2).foregroundStyle(.tertiary)
            }
            if infoHelp != nil {
                Image(systemName: "info.circle")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(valueTint.opacity(0.75))
                    .frame(width: 12, height: 12, alignment: .center)
                    .offset(y: -0.5)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: infoHelp == nil ? nil : .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var valueLabel: some View {
        let text = Text(value).font(.caption2.monospacedDigit())
            .foregroundStyle(valueTint)

        if let infoHelp {
            text.popover(isPresented: $isShowingInfo, arrowEdge: .top) {
                infoPopover(infoHelp)
            }
        } else {
            text
        }
    }

    private func hoverChanged(_ isHovering: Bool) {
        hoverDelayTask?.cancel()

        guard isHovering else {
            isShowingInfo = false
            return
        }

        hoverDelayTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isShowingInfo = true
            }
        }
    }

    private func infoPopover(_ infoHelp: String) -> some View {
        Text(infoHelp)
            .font(.caption)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
        .padding(10)
        .frame(width: 230, alignment: .leading)
    }
}

private struct CodexCreditsRow: View {
    let balance: Double
    let autoReload: CodexAutoReload?

    private static let amber = Color(red: 1.0, green: 0.65, blue: 0.0)
    private static let exhaustedThreshold: Double = 0

    private var isAutoReloadEnabled: Bool {
        autoReload?.isEnabled == true
    }

    private var isExhaustedWithoutReload: Bool {
        balance <= Self.exhaustedThreshold && !isAutoReloadEnabled
    }

    private var shouldShowExceptionBar: Bool {
        isExhaustedWithoutReload && autoReload != nil
    }

    private var valueTint: Color {
        if isAutoReloadEnabled, let autoReload {
            return balance <= autoReload.rechargeThreshold ? Self.amber : .primary
        }
        if balance < 5 { return .red }
        if balance < 20 { return Self.amber }
        return .primary
    }

    private var statusText: String? {
        if isExhaustedWithoutReload { return "reload off" }
        if let autoReload, autoReload.isEnabled, balance <= autoReload.rechargeThreshold {
            return "· auto-reload"
        }
        return nil
    }

    private var statusTint: Color {
        if isExhaustedWithoutReload { return .red }
        return balance <= (autoReload?.rechargeThreshold ?? 0) ? Self.amber : .secondary.opacity(0.65)
    }

    private var target: Double {
        guard let autoReload else { return 1 }
        return max(autoReload.rechargeTarget, autoReload.rechargeThreshold, 1)
    }

    private var fillFraction: Double {
        let depleted = (target - balance) / target
        return min(max(depleted, 0), 1)
    }

    private var balanceText: String {
        formatCodexDollarAmount(balance)
    }

    private func formatCodexDollarAmount(_ credits: Double) -> String {
        let amount = credits / 25.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    private var thresholdFraction: Double {
        guard let autoReload else { return 0 }
        return min(max(autoReload.rechargeThreshold / target, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("Balance:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(balanceText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(valueTint)
                Spacer(minLength: 4)
                if let statusText {
                    Text(statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                }
            }

            if shouldShowExceptionBar, let autoReload {
                GeometryReader { geo in
                    let markerX = geo.size.width * thresholdFraction
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(.fill.quaternary)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(.red)
                            .frame(width: geo.size.width * fillFraction)
                        Rectangle()
                            .fill(.primary.opacity(0.65))
                            .frame(width: 1, height: 7)
                            .offset(x: markerX)
                    }
                }
                .frame(height: 3)

                Text("empty; reload target \(formatCodexDollarAmount(autoReload.rechargeTarget))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .help(helpText)
    }

    private var helpText: String {
        guard let autoReload else {
            return "Codex credits: \(balanceText)"
        }
        if autoReload.isEnabled {
            return "Codex credits: \(balanceText)\nAuto-reload at \(formatCodexDollarAmount(autoReload.rechargeThreshold)); target \(formatCodexDollarAmount(autoReload.rechargeTarget))."
        }
        return "Codex credits: \(balanceText)\nAuto-reload is off."
    }
}

// MARK: - Window capture helper

/// Reads the hosting NSWindow reference as soon as the view is in the hierarchy.
private struct WindowCapture: NSViewRepresentable {
    let onCapture: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onCapture(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onCapture(nsView.window) }
    }
}

// MARK: - Date helpers

private extension Date {
    /// "just now", "1m ago", "5m ago" — suitable for the freshness cue.
    var relativeFormatted: String {
        let elapsed = Int(-timeIntervalSinceNow)
        switch elapsed {
        case ..<10:  return "Just now"
        case ..<60:  return "\(elapsed)s ago"
        case ..<3600:
            let m = elapsed / 60
            return "\(m)m ago"
        default:
            let h = elapsed / 3600
            return "\(h)h ago"
        }
    }
}
