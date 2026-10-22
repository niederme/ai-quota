import SwiftUI
import QuartzCore
import AIQuotaKit
import MobileAccessCore

struct PopoverView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(UpdaterViewModel.self) private var updater
    @Environment(\.openSettings) private var openSettings

    /// Captured reference to the MenuBarExtra NSWindow so we can re-show it
    /// after Settings opens (which steals key focus and causes the window to close).
    @State private var menuBarWindow: NSWindow?
    @State private var selectedService: ServiceType?
    @State private var selectedAccountID: String?
    @State private var hoveredService: ServiceType?
    @State private var focusedService: ServiceType?
    @State private var overviewHeight: CGFloat?
    @State private var navigationPhase: PopoverNavigationPhase = .overview
    @State private var presentationID = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var resetNotice = CodexResetNotice()
    @AppStorage(CodexResetNotice.dismissalKey) private var dismissedResetID = ""
    @State private var demoResetDismissed = false

    private var resetAnnouncement: CodexResetAnnouncement? {
        #if DEMO_MODE
        demoResetDismissed ? nil : CodexResetNotice.demoAnnouncement
        #else
        resetNotice.announcement(dismissedID: dismissedResetID)
        #endif
    }

    private var overviewWidth: CGFloat {
        let visibleWidth = (menuBarWindow?.screen ?? NSScreen.main)?.visibleFrame.width ?? 800
        let accountCount = viewModel.enrolledServices.count + viewModel.additionalAccounts.count
        let ideal: CGFloat = accountCount > 1 ? 652 : 340
        return min(ideal, max(320, visibleWidth - 16))
    }
    private var overviewBodyMaxHeight: CGFloat {
        let screen = menuBarWindow?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 800)
        let top = menuBarWindow?.frame.maxY ?? visible.maxY
        return max(220, min(visible.height * 0.88, top - visible.minY - 16) - 110)
    }
    private var overviewSize: CGSize {
        CGSize(width: overviewWidth, height: overviewHeight ?? 400)
    }
    private var detailSize: CGSize {
        let screen = menuBarWindow?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 800)
        let top = menuBarWindow?.frame.maxY ?? visible.maxY
        let availableHeight = max(300, top - visible.minY - 8)
        // Keep the native panel's horizontal bounds fixed while navigating.
        // With two accounts the former 652 -> 460 point resize visibly swept
        // the detail sheet sideways from its menu-bar anchor.
        return CGSize(width: overviewWidth,
                      height: min(availableHeight, max(visible.height * 0.85, overviewSize.height)))
    }
    private var popoverSize: CGSize {
        navigationPhase.isExpanded ? detailSize : overviewSize
    }
    private var popoverLayoutSize: CGSize {
        // Publishing the compact ideal early makes MenuBarExtra resize the
        // window before AppKit can animate it. Commit it after the native close.
        navigationPhase == .shrinking ? detailSize : popoverSize
    }

    var body: some View {
        MenuBarPopoverHost(
            content: AnyView(pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .environment(viewModel).environment(updater)),
            size: popoverSize,
            compactSize: overviewSize,
            animateResize: !reduceMotion && navigationPhase.resizesWindow,
            presentationID: presentationID,
            onCapture: { menuBarWindow = $0 },
            onResizeFinished: finishNavigationResize
        )
        .onAppear { presentationID += 1 }
        .task(id: viewModel.isCodexAuthenticated) {
            #if !DEMO_MODE
            guard !viewModel.isReadOnlyPreview, viewModel.isCodexAuthenticated else { return }
            while !Task.isCancelled {
                await resetNotice.refresh()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
            #endif
        }
        .onDisappear { resetNavigation() }
        .onChange(of: viewModel.enrolledServices) { _, services in
            if let selectedService, !services.contains(selectedService) { resetNavigation() }
        }
    }

    private var pageContent: some View {
        ZStack(alignment: .topLeading) {
            Group {
                    if !viewModel.enrolledServices.isEmpty || viewModel.hasAdditionalAccounts {
                        gridAuthenticatedContent
                } else {
                    signInContent
                }
            }
            .frame(width: overviewWidth)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if height > 0, navigationPhase == .overview, overviewHeight != height { overviewHeight = height }
            }
            // Crossfade into the overview before the native window begins its
            // close so the returning panel always has content while shrinking.
            .modifier(PopoverPageVisibility(isVisible: navigationPhase.showsOverview,
                                            reduceMotion: reduceMotion, distance: 0, onHidden: {}))
            .allowsHitTesting(navigationPhase == .overview)
            .accessibilityHidden(navigationPhase != .overview)

            if let selectedService {
                    Group {
                        if let selectedAccountID,
                           let session = viewModel.additionalAccounts.first(where: { $0.id == selectedAccountID }) {
                            MacAdditionalAccountDetailView(session: session, height: detailSize.height,
                                                           close: closeService, openSettings: openSettingsKeepingPopover)
                        } else {
                            ServiceDetailView(service: selectedService, height: detailSize.height,
                                              close: closeService, openAccount: openSettingsKeepingPopover)
                        }
                    }
                    .frame(width: detailSize.width)
                    .id(selectedService)
                    // Start revealing the detail as the window expands. Waiting
                    // for the resize completion leaves a blank full-height panel.
                    .modifier(PopoverPageVisibility(isVisible: navigationPhase.showsDetail,
                                                    reduceMotion: reduceMotion, distance: 6,
                                                    onHidden: finishDetailFade))
                    .allowsHitTesting(navigationPhase == .detail)
                    .accessibilityHidden(navigationPhase != .detail)
            }
        }
        .frame(width: popoverLayoutSize.width, height: popoverLayoutSize.height, alignment: .topLeading)
        .clipped()
        .background { popoverSurface }
        .background {
            Button("") { viewModel.manualRefresh() }
                .keyboardShortcut("r", modifiers: .command)
                .hidden()
        }
    }

    private func finishNavigationResize(_ size: CGSize) {
        guard size == popoverSize else { return }
        switch navigationPhase {
        case .expanding:
            navigationPhase = .detail
        case .shrinking:
            selectedService = nil
            selectedAccountID = nil
            navigationPhase = .overview
        default:
            break
        }
    }

    private func closeService() {
        guard navigationPhase == .detail else { return }
        if reduceMotion {
            resetNavigation()
            return
        }
        navigationPhase = .fadingDetail
    }

    private func finishDetailFade() {
        guard navigationPhase == .fadingDetail else { return }
        navigationPhase = .shrinking
    }

    private func resetNavigation() {
        selectedService = nil
        selectedAccountID = nil
        navigationPhase = .overview
        hoveredService = nil
        focusedService = nil
        presentationID += 1
    }

    @ViewBuilder
    private var popoverSurface: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.regularMaterial)
        } else {
            // Sequoia's MenuBarExtra material is substantially more transparent
            // than Tahoe's glass treatment. Stabilize contrast while retaining a
            // small amount of desktop color.
            Rectangle()
                .fill(.regularMaterial)
                .overlay {
                    Color(nsColor: .windowBackgroundColor).opacity(0.92)
                }
        }
    }

    private func openSettingsKeepingPopover() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.async { menuBarWindow?.orderFront(nil) }
    }

    // MARK: - Authenticated layout

    private var visibleServices: [ServiceType] {
        [.codex, .claude].filter { viewModel.enrolledServices.contains($0) }
    }

    private func canOpen(_ service: ServiceType) -> Bool {
        service == .codex
            ? viewModel.isCodexAuthenticated || viewModel.codexUsage != nil
            : viewModel.isClaudeAuthenticated || viewModel.claudeUsage != nil
    }

    private func openService(_ service: ServiceType) {
        guard canOpen(service), navigationPhase == .overview else { return }
        hoveredService = nil
        focusedService = nil
        selectedService = service
        selectedAccountID = nil
        navigationPhase = reduceMotion ? .detail : .expanding
    }

    private func openAccount(_ account: ConnectedAccount) {
        guard navigationPhase == .overview else { return }
        if account.connectionKind == .legacyPrimary {
            openService(account.provider)
        } else {
            selectedService = account.provider
            selectedAccountID = account.id
            navigationPhase = reduceMotion ? .detail : .expanding
        }
    }

    private var gridAuthenticatedContent: some View {
        VStack(spacing: 0) {
            header
            ForEach(errorBanners) { banner in
                errorBanner(banner)
            }
            if viewModel.isCodexAuthenticated { resetNoticeRow }
            MacAccountGridView(width: overviewWidth, maxHeight: overviewBodyMaxHeight,
                               openAccount: openAccount, openSettings: openSettingsKeepingPopover)
            updateAvailableRow
            Divider()
            footer
        }
    }

    private func service(at x: CGFloat) -> ServiceType? {
        guard !visibleServices.isEmpty else { return nil }
        let column = min(visibleServices.count - 1, max(0, Int(x / (overviewWidth / CGFloat(visibleServices.count)))))
        return visibleServices[column]
    }

    // One tracking region spans both rows, including their padding and divider.
    // Child controls such as Refresh and Connect keep their own button actions.
    private var serviceArea: some View {
        VStack(spacing: 0) {
            gaugeRow.padding(.top, 16).padding(.bottom, 10)
            statsRow
        }
        .contentShape(Rectangle())
        .background {
            HStack(spacing: 0) {
                ForEach(visibleServices, id: \.self) { service in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary)
                        .foregroundStyle(.primary)
                        .opacity(hoveredService == service || focusedService == service ? 1 : 0)
                        .frame(maxWidth: .infinity)
                        .padding(5)
                }
            }.allowsHitTesting(false)
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoveredService = service(at: location.x).flatMap { canOpen($0) ? $0 : nil }
            case .ended:
                hoveredService = nil
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredService)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: focusedService)
        .onTapGesture(coordinateSpace: .local) { location in
            if let service = service(at: location.x) { openService(service) }
        }
    }

    private func serviceTarget<Content: View>(_ service: ServiceType, @ViewBuilder content: () -> Content) -> some View {
        let name = service == .codex ? "Codex" : "Claude"
        return ServiceFocusRegion(enabled: canOpen(service) && navigationPhase == .overview,
                                  content: content()) { focused in
            if focused {
                focusedService = service
            } else if focusedService == service {
                focusedService = nil
            }
        }
            .onKeyPress(keys: [.return, .space]) { _ in
                guard canOpen(service) else { return .ignored }
                openService(service)
                return .handled
            }
            .accessibilityAction(named: Text("View \(name) details")) { openService(service) }
            .accessibilityHint(canOpen(service) ? "Opens \(name) analytics and statistics" : "")
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        VStack(spacing: 0) {
            header

            ForEach(errorBanners) { banner in
                errorBanner(banner)
                Divider()
            }

            if viewModel.isCodexAuthenticated {
                resetNoticeRow
            }

            serviceArea

            updateAvailableRow
            Divider()
            footer
        }
    }

    @ViewBuilder
    private var resetNoticeRow: some View {
        if let announcement = resetAnnouncement {
            MacResetNoticeBanner(title: announcement.title) {
                NSWorkspace.shared.open(CodexResetNotice.website)
            } onDismiss: {
                    #if DEMO_MODE
                    demoResetDismissed = true
                    #else
                    dismissedResetID = announcement.id
                    #endif
            }
        }
    }

    // MARK: - Gauge slots

    @ViewBuilder
    private var codexGaugeSlot: some View {
        if viewModel.isCodexAuthenticated {
            if let u = viewModel.codexUsage {
                if u.reportedWindowShape == nil,
                   let budget = u.monthlyBudget,
                   let used = budget.used, let limit = budget.limit,
                   used.isFinite, used >= 0, limit.isFinite, limit > 0 {
                    BudgetGaugeView(
                        used: used, limit: limit,
                        usedText: budgetValue(used, unit: budget.unit),
                        limitText: budgetValue(limit, unit: budget.unit),
                        unitLabel: budget.unit?.lowercased() == "credit" ? "credits this month"
                            : (budget.unit?.lowercased() == "usd" ? "monthly spend" : "monthly allowance"),
                        icon: "logo-openai", label: "Codex", resetAt: budget.resetAt,
                        isRefreshing: viewModel.isCodexLoading,
                        onRefresh: { viewModel.manualRefresh() }
                    )
                } else if u.reportedWindowShape != nil {
                    let hasHourlyWindow = u.reportedWindowShape == .dual
                    CircularGaugeView(
                        primaryPercent: hasHourlyWindow ? u.hourlyUsedPercent : u.weeklyUsedPercent,
                        primaryLimitReached: hasHourlyWindow ? u.hourlyUsedPercent >= 100 : u.isWeeklyExhausted,
                        showsPrimaryMetric: true,
                        secondaryPercent: u.weeklyUsedPercent,
                        secondaryLimitReached: u.isWeeklyExhausted,
                        showsSecondaryMetric: hasHourlyWindow,
                        isLoading: false,
                        icon: "logo-openai",
                        label: "Codex",
                        primaryLabel: hasHourlyWindow ? formatWindowDuration(u.hourlyWindowSeconds) : "7d",
                        secondaryLabel: "7d",
                        resetAt: hasHourlyWindow ? (u.hourlyResetAt == .distantFuture ? nil : u.hourlyResetAt) : (u.weeklyResetAt == .distantFuture ? nil : u.weeklyResetAt),
                        weeklyResetAt: u.weeklyResetAt == .distantFuture ? nil : u.weeklyResetAt,
                        isRefreshing: viewModel.isCodexLoading,
                        onRefresh: { viewModel.manualRefresh() }
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Codex usage")
                    .accessibilityValue(codexAccessibilitySummary(u))
                } else {
                    unavailableCodexUsage
                }
            } else {
                if viewModel.isCodexLoading {
                    CircularGaugeView(
                        primaryPercent: 0, primaryLimitReached: false,
                        showsPrimaryMetric: true,
                        secondaryPercent: 0, secondaryLimitReached: false,
                        showsSecondaryMetric: true,
                        isLoading: true, icon: "logo-openai",
                        label: "Codex", primaryLabel: "5h", secondaryLabel: "7d",
                        resetAt: nil, weeklyResetAt: nil, isRefreshing: true, onRefresh: {}
                    )
                } else {
                    unavailableCodexUsage
                }
            }
        } else if viewModel.isCodexRecovering {
            loadingGauge(icon: "logo-openai", label: "Codex")
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
                if u.primaryMetric.kind == .spendLimit,
                   let spend = u.spendLimit,
                   spend.used.isFinite, spend.used >= 0,
                   spend.limit.isFinite, spend.limit > 0 {
                    BudgetGaugeView(
                        used: spend.used, limit: spend.limit,
                        usedText: budgetValue(spend.used, unit: spend.currencyCode),
                        limitText: budgetValue(spend.limit, unit: spend.currencyCode),
                        unitLabel: spend.currencyCode?.uppercased() == "USD" ? "monthly spend" : "monthly allowance",
                        icon: "logo-claude", label: "Claude Code", resetAt: nil,
                        isRefreshing: viewModel.isClaudeLoading,
                        onRefresh: { viewModel.manualRefresh() }
                    )
                } else {
                    CircularGaugeView(
                        primaryPercent: u.usedPercent,
                        primaryLimitReached: u.limitReached,
                        showsPrimaryMetric: true,
                        secondaryPercent: Int(u.sevenDayUtilization?.rounded() ?? 0),
                        secondaryLimitReached: (u.sevenDayUtilization ?? 0) >= 100,
                        showsSecondaryMetric: u.primaryMetric.kind != .sevenDay && u.sevenDayUtilization != nil,
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
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Claude usage")
                    .accessibilityValue(claudeAccessibilitySummary(u))
                }
            } else {
                CircularGaugeView(
                    primaryPercent: 0, primaryLimitReached: false,
                    showsPrimaryMetric: true,
                    secondaryPercent: 0, secondaryLimitReached: false,
                    showsSecondaryMetric: true,
                    isLoading: true, icon: "logo-claude",
                    label: "Claude Code", primaryLabel: "5h", secondaryLabel: "7d",
                    resetAt: nil, weeklyResetAt: nil, isRefreshing: true, onRefresh: {}
                )
            }
        } else if viewModel.isClaudeRecovering {
            loadingGauge(icon: "logo-claude", label: "Claude Code")
        } else {
            connectGauge(icon: "logo-claude", label: "Claude Code") {
                Task { await viewModel.signInClaude() }
            }
        }
    }

    private var codexColumn: some View {
        VStack(spacing: 0) {
            codexGaugeSlot
            if viewModel.isCodexAuthenticated,
               let history = viewModel.codexTokenHistory,
               CodexTokenHistoryView.hasVisibleData(history) {
                CodexTokenHistoryView(history: history, availableWidth: max(1, overviewWidth / CGFloat(visibleServices.count) - 28))
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: viewModel.isCodexAuthenticated) {
            if viewModel.isCodexAuthenticated { viewModel.refreshTokenHistory() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Codex service")
        .accessibilityIdentifier("codexServiceColumn")
    }

    @ViewBuilder
    private var gaugeRow: some View {
        if viewModel.isCodexEnrolled && viewModel.isClaudeEnrolled {
            HStack(alignment: .top, spacing: 0) {
                serviceTarget(.codex) { codexColumn }.frame(maxWidth: .infinity)
                Divider()
                serviceTarget(.claude) { claudeGaugeSlot }.frame(maxWidth: .infinity)
            }
        } else if viewModel.isCodexEnrolled {
            serviceTarget(.codex) { codexColumn }
        } else {
            serviceTarget(.claude) { claudeGaugeSlot }
        }
    }

    @ViewBuilder
    private var statsRow: some View {
        let bothEnrolled = viewModel.isCodexEnrolled && viewModel.isClaudeEnrolled
        let hasCodexStats = viewModel.isCodexEnrolled && viewModel.codexUsage != nil
        let hasClaudeStats = viewModel.isClaudeEnrolled && viewModel.claudeUsage != nil

        if hasCodexStats || hasClaudeStats {
            Divider()
            if bothEnrolled {
                HStack(alignment: .top, spacing: 0) {
                    codexSecondaryStats.padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    claudeSecondaryStats.padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 7)
            } else if hasCodexStats {
                codexSecondaryStats.padding(.horizontal, 14).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                claudeSecondaryStats.padding(.horizontal, 14).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func codexAccessibilitySummary(_ u: CodexUsage) -> String {
        var lines: [String]
        if u.reportedWindowShape == .dual {
            lines = [
                "\(formatWindowDuration(u.hourlyWindowSeconds)) window: \(u.hourlyUsedPercent)% used",
                "7-day window: \(u.weeklyUsedPercent)% used",
            ]
        } else if u.reportedWindowShape == .weeklyOnly {
            lines = [
                "5h window: not currently reported",
                "7-day window: \(u.weeklyUsedPercent)% used",
            ]
        } else { lines = ["Usage unavailable"] }
        if let balance = u.creditBalance { lines.append("Credit balance: \(formatCodexDollarAmount(balance))") }
        if let spent = u.bonusCreditsSpentThisMonth, spent > 0 {
            lines.append("Credits used: \(formatCodexDollarAmount(spent))")
        }
        if let local = u.approxLocalMessages, local.count == 2 {
            lines.append("Local messages: ~\(local[0]) / \(local[1])")
        }
        if let cloud = u.approxCloudMessages, cloud.count == 2 {
            lines.append("Cloud messages: ~\(cloud[0]) / \(cloud[1])")
        }
        lines.append("Plan: \(u.displayPlan)")
        return lines.joined(separator: "\n")
    }

    private var unavailableCodexUsage: some View {
        VStack(spacing: 8) {
            Text("Codex").font(.headline.bold())
            Text("Usage unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Refresh") { viewModel.manualRefresh() }
                .controlSize(.small)
        }
        .frame(width: 114, height: 114)
    }

    private func budgetValue(_ amount: Double, unit: String?) -> String {
        let digits = amount == amount.rounded() ? 0 : 2
        if let unit, unit.count == 3, unit.lowercased() != "credit" {
            return amount.formatted(.currency(code: unit.uppercased()).precision(.fractionLength(digits)))
        }
        return amount.formatted(.number.precision(.fractionLength(digits)))
    }

    private func claudeAccessibilitySummary(_ u: ClaudeUsage) -> String {
        var lines = [
            "\(u.primaryMetricLabel) usage: \(u.primaryMetric.utilization.map { "\(Int($0.rounded()))% used" } ?? "unknown")",
        ]
        if u.primaryMetric.kind != .sevenDay, let sevenDay = u.sevenDayUtilization {
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
                    .stroke(.fill.tertiary, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.fill.tertiary, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
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
                compactRow("Plan", usage.displayPlan)
                if let balance = usage.creditBalance {
                    CodexCreditsRow(balance: balance, autoReload: autoReload)
                }
                if let spent = usage.bonusCreditsSpentThisMonth, spent > 0 {
                    compactRow(
                        "Credits used",
                        formatCodexDollarAmount(spent),
                        labelTint: .warningAmber,
                        valueTint: .warningAmber,
                        infoTitle: "Estimated Monthly Spend",
                        infoHelp: codexSpentHelpText,
                        stacked: true
                    )
                }
            }
        }
    }

    private func loadingGauge(icon: String, label: String) -> some View {
        CircularGaugeView(
            primaryPercent: 0,
            primaryLimitReached: false,
            showsPrimaryMetric: true,
            secondaryPercent: 0,
            secondaryLimitReached: false,
            showsSecondaryMetric: true,
            isLoading: true,
            icon: icon,
            label: label,
            primaryLabel: "5h",
            secondaryLabel: "7d",
            resetAt: nil,
            weeklyResetAt: nil,
            isRefreshing: true,
            onRefresh: {}
        )
    }

    @ViewBuilder
    private var claudeSecondaryStats: some View {
        if let usage = viewModel.claudeUsage {
            VStack(alignment: .leading, spacing: 6) {
                compactRow("Plan", usage.planDisplayName)
                if let credits = usage.usageCredits, credits.spent > 0 {
                    let tint: Color = credits.limitReached || credits.severity == .critical
                        ? .critical
                        : .warningAmber
                    VStack(alignment: .leading, spacing: 2) {
                        compactRow(
                            "Credits used",
                            formatUsageCredits(credits),
                            labelTint: tint,
                            valueTint: tint,
                            infoTitle: "Fable 5 & Post-Limit Usage",
                            infoHelp: claudeUsageCreditsHelpText,
                            stacked: true
                        )
                        if usage.shouldExplainUsageCreditsSeparation {
                            Text("Separate from plan limits")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private func compactRow(
        _ label: String,
        _ value: String,
        labelTint: Color = .secondary,
        valueTint: Color = .primary,
        suffix: String? = nil,
        infoTitle: String? = nil,
        infoHelp: String? = nil,
        stacked: Bool = false
    ) -> some View {
        CompactStatRow(
            label: label,
            value: value,
            labelTint: labelTint,
            valueTint: valueTint,
            suffix: suffix,
            infoTitle: infoTitle,
            infoHelp: infoHelp,
            stacked: stacked
        )
    }

    private var codexSpentHelpText: String {
        "AIQuota sums \(currentMonthName)’s usage-credit events and converts them at 25 credits = $1."
    }

    private var claudeUsageCreditsHelpText: String {
        "Claude reports both as one monthly total and doesn’t provide a reliable breakdown."
    }

    private var currentMonthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: .now)
    }

    private func formatBonusSpend(_ bonus: ClaudeUsage.BonusUsage) -> String {
        if let currencyCode = bonus.currencyCode {
            return formatCurrencyAmount(bonus.spent, currencyCode: currencyCode)
        }
        return formatCreditAmount(bonus.spent)
    }

    private func formatUsageCredits(_ credits: ClaudeUsage.UsageCredits) -> String {
        if let currencyCode = credits.currencyCode {
            return formatCurrencyAmount(credits.spent, currencyCode: currencyCode)
        }
        return formatCreditAmount(credits.spent)
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
            Image("AppBrandIcon")
                .resizable()
                .frame(width: 20, height: 20)
            Text("AIQuota").font(.headline)
            Spacer()
            let accountCount = viewModel.enrolledServices.count + viewModel.additionalAccounts.count
            if accountCount > 1 {
                Text("\(accountCount) accounts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        Divider()
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
                Image("AppBrandIcon")
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
            updateAvailableRow
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
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
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

    @ViewBuilder
    private var updateAvailableRow: some View {
        if let version = updater.availableUpdateVersion {
            Divider()
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.warningAmber)
                    .frame(width: 7, height: 7)
                Text("Update Available")
                    .fontWeight(.medium)
                Text(version)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Update…") { updater.checkForUpdates() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open the AIQuota update")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
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
                .foregroundStyle(Color.warningAmber).font(.footnote)
            Text(banner.message)
                .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            if let signIn = banner.signIn {
                Button("Sign In", action: signIn)
                    .buttonStyle(.borderless)
                    .font(.footnote.bold())
                    .foregroundStyle(Color.warningAmber)
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
        .background(Color.warningAmber.opacity(0.1))
    }

    // MARK: - Helpers

    private func formatWindowDuration(_ seconds: Int) -> String {
        let days = seconds / 86_400
        if days > 0, seconds.isMultiple(of: 86_400) { return "\(days)d" }
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
    let infoTitle: String?
    let infoHelp: String?

    var stacked: Bool = false

    var body: some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: -2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 4))
        layout {
            Text(label + ":")
                .font(.caption2)
                .foregroundStyle(labelTint)
                .fixedSize(horizontal: false, vertical: true)
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 4) {
            valueLabel
            if let suffix {
                Text(suffix)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if let infoHelp {
                InfoPopoverButton(
                    title: infoTitle ?? label,
                    text: infoHelp,
                    tint: valueTint
                )
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: infoHelp == nil ? nil : .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var valueLabel: some View {
        Text(value)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(valueTint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }
}

private struct InfoPopoverButton: View {
    let title: String
    let text: String
    let tint: Color

    @State private var isPresented = false
    @State private var isPinned = false
    @State private var hoverDelayTask: Task<Void, Never>?

    var body: some View {
        Button {
            hoverDelayTask?.cancel()
            if isPresented, isPinned {
                isPinned = false
                isPresented = false
            } else {
                isPinned = true
                isPresented = true
            }
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(tint.opacity(0.75))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: hoverChanged)
        .popover(isPresented: presentationBinding, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
                .padding(9)
                .frame(width: 210, alignment: .leading)
        }
        .accessibilityLabel("About \(title)")
        .accessibilityHint(text)
        .onDisappear {
            hoverDelayTask?.cancel()
        }
    }

    private var presentationBinding: Binding<Bool> {
        Binding(
            get: { isPresented },
            set: { newValue in
                isPresented = newValue
                if !newValue {
                    isPinned = false
                }
            }
        )
    }

    private func hoverChanged(_ isHovering: Bool) {
        hoverDelayTask?.cancel()

        guard isHovering else {
            if !isPinned {
                isPresented = false
            }
            return
        }
        guard !isPresented else { return }

        hoverDelayTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isPresented = true
            }
        }
    }
}

private struct CodexCreditsRow: View {
    let balance: Double
    let autoReload: CodexAutoReload?

    private static let amber = Color.warningAmber
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
        if balance < 5 { return .critical }
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
        if isExhaustedWithoutReload { return .critical }
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

    private var balanceAmount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("Credit balance:").font(.caption2).foregroundStyle(.secondary)
            Text(balanceText).font(.caption2.monospacedDigit()).foregroundStyle(valueTint)
        }.fixedSize()
    }
    @ViewBuilder private var reloadStatus: some View {
        if let statusText {
            Text(statusText).font(.caption2.weight(.semibold)).foregroundStyle(statusTint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var balanceLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            balanceAmount
            Spacer(minLength: 4)
            reloadStatus.fixedSize()
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                balanceLine
                VStack(alignment: .leading, spacing: 2) {
                    balanceAmount
                    reloadStatus
                }
            }

            if shouldShowExceptionBar, let autoReload {
                GeometryReader { geo in
                    let markerX = geo.size.width * thresholdFraction
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(.fill.quaternary)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.critical)
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

// MARK: - Staged menu bar navigation

/// Focus belongs to the hosting graph containing the actual service controls.
/// Report it back to the full-column hover surface without a system focus ring.
private struct ServiceFocusRegion<Content: View>: View {
    let enabled: Bool
    let content: Content
    let onFocusChanged: (Bool) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        content
            .focusable(enabled)
            .focused($focused)
            .focusEffectDisabled()
            .onChange(of: focused) { _, focused in onFocusChanged(focused) }
    }
}

/// Fade inside the nested hosting graph so its completion represents the
/// actual rendered fade, including an interrupted fade-in on a quick Back.
private struct PopoverPageVisibility: ViewModifier {
    let isVisible: Bool
    let reduceMotion: Bool
    let distance: CGFloat
    let onHidden: () -> Void
    @State private var opacity = 0.0
    @State private var animationID = 0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: reduceMotion ? 0 : (1 - opacity) * distance)
            .onChange(of: isVisible, initial: true) { _, visible in
                animationID += 1
                let currentAnimation = animationID
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14), completionCriteria: .removed) {
                    opacity = visible ? 1 : 0
                } completion: {
                    guard !visible, animationID == currentAnimation else { return }
                    onHidden()
                }
            }
            .onDisappear { animationID += 1 }
    }
}

private enum PopoverNavigationPhase {
    case overview, expanding, detail, fadingDetail, shrinking

    var showsOverview: Bool {
        self == .overview || self == .fadingDetail || self == .shrinking
    }
    var showsDetail: Bool { self == .expanding || self == .detail }
    var isExpanded: Bool {
        self == .expanding || self == .detail || self == .fadingDetail
    }
    var resizesWindow: Bool { self == .expanding || self == .shrinking }
}

/// Keep page layout independent of MenuBarExtra's cached compact proposal.
/// Resize the native window from its menu-bar anchor, then reveal the page
/// after both the frame animation and the hosted layout have completed.
private struct MenuBarPopoverHost: NSViewRepresentable {
    let content: AnyView
    let size: CGSize
    let compactSize: CGSize
    let animateResize: Bool
    let presentationID: Int
    let onCapture: (NSWindow?) -> Void
    let onResizeFinished: (CGSize) -> Void

    func makeNSView(context: Context) -> MenuBarPopoverContainer {
        MenuBarPopoverContainer(content: content, size: size, compactSize: compactSize)
    }

    func updateNSView(_ view: MenuBarPopoverContainer, context: Context) {
        view.host.rootView = content
        view.onCapture = onCapture
        view.onResizeFinished = onResizeFinished
        view.compactSize = compactSize
        view.resetAnchor(for: presentationID)
        view.resize(to: size, animate: animateResize)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: MenuBarPopoverContainer,
                      context: Context) -> CGSize? {
        // MenuBarExtra can keep proposing the previous (taller) window size.
        // Reporting that stale proposal made the overview retain empty space
        // below the footer. The native window handles detail-page expansion;
        // SwiftUI always advertises the measured compact content size.
        view.compactSize
    }
}

@MainActor
private protocol ManualPopoverSizing: AnyObject {
    func stopAutomaticPopoverSizing()
}

extension NSHostingView: ManualPopoverSizing {
    fileprivate func stopAutomaticPopoverSizing() { sizingOptions = [] }
}

private final class MenuBarPopoverContainer: NSView {
    let host: NSHostingView<AnyView>
    let initialSize: CGSize
    var compactSize: CGSize {
        didSet { if compactSize != oldValue { invalidateIntrinsicContentSize() } }
    }
    var onCapture: (NSWindow?) -> Void = { _ in }
    var onResizeFinished: (CGSize) -> Void = { _ in }
    private var desiredSize: CGSize
    private var appliedSize: CGSize?
    private var topRight: CGPoint?
    private var presentationID: Int?
    private var resizeGeneration = 0

    init(content: AnyView, size: CGSize, compactSize: CGSize) {
        host = NSHostingView(rootView: content)
        initialSize = size
        self.compactSize = compactSize
        desiredSize = size
        super.init(frame: CGRect(origin: .zero, size: size))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        host.frame = bounds
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    // The native window owns expanded sizing. Advertising the detail page as
    // this view's intrinsic size makes MenuBarExtra independently resize and
    // reposition the same window midway through our anchored animation.
    override var intrinsicContentSize: NSSize { compactSize }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        appliedSize = nil
        topRight = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onCapture(self.window)
            self.resize(to: self.desiredSize, animate: false)
        }
    }

    func resetAnchor(for presentationID: Int) {
        guard self.presentationID != presentationID else { return }
        self.presentationID = presentationID
        topRight = nil
        appliedSize = nil
        resizeGeneration += 1
    }

    func resize(to size: CGSize, animate: Bool) {
        if desiredSize != size {
            desiredSize = size
        }
        guard appliedSize != size else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, self.desiredSize == size,
                  self.appliedSize != size else { return }
            let initial = self.appliedSize == nil
            self.appliedSize = size
            self.resizeGeneration += 1
            let generation = self.resizeGeneration
            let animated = animate && !initial && window.isVisible
            (window.contentView as? any ManualPopoverSizing)?.stopAutomaticPopoverSizing()
            window.contentMinSize = .zero
            window.contentMaxSize = CGSize(width: 10_000, height: 10_000)
            // Finish removing the invisible page graphs before shrinking.
            if size.height < (window.contentView?.bounds.height ?? window.frame.height) {
                self.host.layoutSubtreeIfNeeded()
            }

            var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
            let anchor = self.topRight ?? CGPoint(x: window.frame.maxX, y: window.frame.maxY)
            frame.origin = CGPoint(x: anchor.x - frame.width, y: anchor.y - frame.height)
            if !window.isVisible {
                self.topRight = nil
                window.setFrame(frame, display: false)
                self.onResizeFinished(size)
                return
            }
            if animated { self.topRight = anchor }
            if let screen = window.screen {
                let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
                frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animated ? 0.32 : 0
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                if animated {
                    window.animator().setFrame(frame, display: true)
                } else {
                    window.setFrame(frame, display: true)
                }
            } completionHandler: { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.resizeGeneration == generation else { return }
                    window.contentView?.needsLayout = true
                    window.contentView?.layoutSubtreeIfNeeded()
                    self.onResizeFinished(size)
                }
            }
        }
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
