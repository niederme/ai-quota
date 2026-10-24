import SwiftUI
import AIQuotaKit

/// Queries verified current windows without turning cached readings into samples.
struct MacQuotaInsightRow: View {
    @Environment(QuotaViewModel.self) private var viewModel
    var accountID: String? = nil
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @State private var insight: Insight?
    @State private var dismissedScopes: Set<QuotaForecastScope> = []

    private struct Insight {
        let forecast: QuotaExhaustionForecast
        let query: Query
    }
    private struct Query: Hashable {
        let accountID: String
        let provider: String
        let identity: String
        let source: String
        let plan: String
        let label: String
        let fetchedAt: Date
        let fiveHourReset: Date?
        let weeklyReset: Date?
        let monthlyReset: Date?
    }
    private struct RefreshID: Hashable {
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
                return Query(accountID: account.id, provider: "claude", identity: identity,
                    source: usage.source.rawValue, plan: usage.planLabel.rawValue,
                    label: "\(account.displayLabel) Claude", fetchedAt: usage.fetchedAt,
                    fiveHourReset: eligible(usage.fiveHourUtilization) ? usage.fiveHourResetsAt : nil,
                    weeklyReset: eligible(usage.sevenDayUtilization) ? usage.sevenDayResetsAt : nil,
                    monthlyReset: nil)
            }
            if !isolated {
                guard viewModel.isCodexAuthenticated, viewModel.codexError == nil else { return nil }
            }
            let usage = isolated ? session?.codexUsage : viewModel.codexUsage
            guard let usage, let identity = usage.accountID, !identity.isEmpty,
                  identity == account.workspaceID, let source = usage.quotaSource, source != .unknown else { return nil }
            let hasWindows = usage.reportedWindowShape != nil
            let short = usage.reportedWindowShape == .dual && usage.hourlyWindowSeconds == 18000
                && eligible(Double(usage.hourlyUsedPercent))
            let weekly = hasWindows && eligible(Double(usage.weeklyUsedPercent))
            let budget = usage.displayableMonthlyBudget
            let monthly = !hasWindows && eligible(budget?.used, limit: budget?.limit ?? 0)
            return Query(accountID: account.id, provider: "codex", identity: identity,
                source: source.rawValue, plan: usage.planType,
                label: "\(account.displayLabel) Codex", fetchedAt: usage.fetchedAt,
                fiveHourReset: short ? usage.hourlyResetAt : nil,
                weeklyReset: weekly ? usage.weeklyResetAt : nil,
                monthlyReset: monthly ? budget?.resetAt : nil)
        }
        #endif
    }

    private func eligible(_ used: Double?, limit: Double = 100) -> Bool {
        used.map { $0.isFinite && limit.isFinite && limit > 0 && $0 > 0 && $0 < limit } == true
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let currentQueries = queries
            VStack(spacing: 0) {
                // A new reading, rename, account switch, correction, or reset hides
                // old content synchronously while the async query is refreshed.
                if let insight, !dismissedScopes.contains(insight.forecast.scope),
                   currentQueries.contains(insight.query),
                   matches(insight.forecast, query: insight.query),
                   insight.forecast.earliest > context.date,
                   insight.forecast.validUntil > context.date {
                    MacQuotaInsightBanner(forecast: insight.forecast, accountLabel: insight.query.label) {
                        self.insight = nil
                        dismissedScopes.insert(insight.forecast.scope)
                        Task { await QuotaInsightStore.shared.dismiss(insight.forecast.scope) }
                    }
                }
            }
            .task(id: RefreshID(queries: currentQueries, minute: Int(context.date.timeIntervalSince1970 / 60))) {
                var candidates: [Insight] = []
                for query in currentQueries {
                    let forecasts = await QuotaInsightStore.shared.forecasts(accountID: query.accountID,
                        provider: query.provider, identity: query.identity, source: query.source,
                        plan: query.plan, now: context.date)
                    candidates += forecasts.filter { matches($0, query: query) }
                        .map { Insight(forecast: $0, query: query) }
                }
                guard !Task.isCancelled else { return }
                insight = candidates.min { $0.forecast.earliest < $1.forecast.earliest }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
    }

    private func matches(_ forecast: QuotaExhaustionForecast, query: Query) -> Bool {
        let scope = forecast.scope
        let reset: Date? = switch scope.window {
        case .fiveHour: query.fiveHourReset
        case .weekly: query.weeklyReset
        case .monthly: query.monthlyReset
        }
        return scope.accountID == query.accountID && scope.provider == query.provider
            && scope.identity == query.identity && scope.source == query.source && scope.plan == query.plan
            && reset.map { abs($0.timeIntervalSince(scope.resetAt)) < 1 } == true
    }
}
