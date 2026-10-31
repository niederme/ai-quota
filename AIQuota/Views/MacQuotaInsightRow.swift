import SwiftUI
import AIQuotaKit

/// Queries verified current windows without turning cached readings into samples.
struct MacQuotaInsightRow: View {
    @Environment(QuotaViewModel.self) private var viewModel
    var accountID: String? = nil
    var inset = true
    var announcementTitle: String? = nil
    var onReadMore: () -> Void = {}
    var onDismissAnnouncement: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @State private var insight: Insight?
    @State private var dismissedScopes: Set<QuotaForecastScope> = []

    private struct Insight {
        let forecast: QuotaExhaustionForecast
        let query: Query
    }
    private struct Query: Equatable {
        let label: String
        let inputs: [QuotaForecastInput]
        let history: QuotaForecastDailyHistory?
    }
    private struct RefreshID: Equatable {
        let queries: [Query]
        let minute: Int
    }
    private var queries: [Query] {
        #if DEMO_MODE
        return []
        #else
        guard !viewModel.isReadOnlyPreview else { return [] }
        return AccountRegistry.orderedAccounts().compactMap { account in
            guard accountID == nil || account.id == accountID else { return nil }
            let isolated = account.connectionKind == .isolated
            let session = isolated ? viewModel.additionalAccounts.first { $0.id == account.id } : nil
            if isolated {
                guard let session, session.isAuthenticated, session.issue == nil else { return nil }
            }
            if account.provider == .claude {
                if !isolated {
                    guard viewModel.isClaudeAuthenticated, viewModel.claudeError == nil else { return nil }
                }
                let usage = isolated ? session?.claudeUsage : viewModel.claudeUsage
                guard let usage, usage.source == .web, let identity = usage.quotaScopeID,
                      !identity.isEmpty, identity == account.workspaceID else { return nil }
                let inputs = [(QuotaForecastScope.Window.fiveHour, usage.fiveHourUtilization, usage.fiveHourResetsAt, 18000.0),
                              (.weekly, usage.sevenDayUtilization, usage.sevenDayResetsAt, 604800.0)].compactMap { window, used, reset, duration -> QuotaForecastInput? in
                    guard let used, let reset else { return nil }
                    return .init(scope: .init(accountID: account.id, provider: "claude", identity: identity,
                        source: usage.source.rawValue, plan: usage.planLabel.rawValue, window: window, resetAt: reset),
                        usedPercent: used, duration: duration, fetchedAt: usage.fetchedAt)
                }
                // The available Enterprise spend report is organization-scoped;
                // do not apply it to a personal allowance without verified matching scope.
                return Query(label: "\(account.displayLabel) Claude", inputs: inputs, history: nil)
            }
            if !isolated {
                guard viewModel.isCodexAuthenticated, viewModel.codexError == nil else { return nil }
            }
            let usage = isolated ? session?.codexUsage : viewModel.codexUsage
            guard let usage, let identity = usage.accountID, !identity.isEmpty,
                  identity == account.workspaceID, let source = usage.quotaSource, source != .unknown else { return nil }
            var inputs: [QuotaForecastInput] = []
            func append(_ window: QuotaForecastScope.Window, used: Double, duration: Double, reset: Date) {
                inputs.append(.init(scope: .init(accountID: account.id, provider: "codex", identity: identity,
                    source: source.rawValue, plan: usage.planType, window: window, resetAt: reset),
                    usedPercent: used, duration: duration, fetchedAt: usage.fetchedAt))
            }
            if usage.reportedWindowShape == .dual, usage.hourlyWindowSeconds == 18000 {
                append(.fiveHour, used: Double(usage.hourlyUsedPercent), duration: 18000, reset: usage.hourlyResetAt)
            }
            if usage.reportedWindowShape != nil {
                append(.weekly, used: Double(usage.weeklyUsedPercent), duration: 604800, reset: usage.weeklyResetAt)
            }
            let creditHistory = isolated ? session?.codexUsageHistory : viewModel.codexUsageHistory
            let historyFailed = isolated ? session?.usageHistoryFailed == true : viewModel.usageHistoryFailed
            let tokenHistory = isolated ? session?.codexTokenHistory : viewModel.codexTokenHistory
            var history = historyFailed ? nil : creditHistory.map(QuotaForecastDailyHistory.init)
            if history == nil, let tokenHistory, tokenHistory.isAttributed(toWorkspaceID: identity) {
                history = .init(values: tokenHistory.tokensByDate, fetchedAt: tokenHistory.fetchedAt)
            }
            return Query(label: "\(account.displayLabel) Codex", inputs: inputs, history: history)
        }
        #endif
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let currentQueries = queries
            let visible = insight.flatMap { candidate -> Insight? in
                guard !dismissedScopes.contains(candidate.forecast.scope),
                      currentQueries.contains(candidate.query),
                      candidate.forecast.scope.resetAt > context.date,
                      candidate.forecast.validUntil > context.date else { return nil }
                return candidate
            }
            VStack(spacing: 0) {
                if announcementTitle != nil || visible != nil {
                    MacAlertGroup {
                        if let announcementTitle {
                            MacResetNoticeBanner(title: announcementTitle, onReadMore: onReadMore) {
                                withAnimation(reduceMotion ? nil : .default) { onDismissAnnouncement() }
                            }
                        }
                        if announcementTitle != nil && visible != nil {
                            Color.overviewTrack.frame(height: 1 / displayScale)
                                .padding(.leading, 40).accessibilityHidden(true)
                        }
                        // A changed reading or reset hides stale content synchronously.
                        if let visible {
                            MacQuotaInsightBanner(forecast: visible.forecast, accountLabel: visible.query.label, inset: false) {
                                withAnimation(reduceMotion ? nil : .default) {
                                    insight = nil
                                    dismissedScopes.insert(visible.forecast.scope)
                                }
                                Task { await QuotaInsightStore.shared.dismiss(visible.forecast.scope) }
                            }
                        }
                    }
                    .padding(.horizontal, inset ? 16 : 0)
                    .padding(.vertical, inset ? 8 : 0)
                }
            }
            .task(id: RefreshID(queries: currentQueries, minute: Int(context.date.timeIntervalSince1970 / 60))) {
                var candidates: [Insight] = []
                for query in currentQueries {
                    let estimates = query.inputs.compactMap {
                        QuotaExhaustionForecast.estimate($0, history: query.history, now: context.date)
                    }
                    let forecasts = await QuotaInsightStore.shared.visible(estimates)
                    candidates += forecasts.map { Insight(forecast: $0, query: query) }
                }
                guard !Task.isCancelled else { return }
                insight = candidates.min { $0.forecast.scope.resetAt < $1.forecast.scope.resetAt }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
    }

}
