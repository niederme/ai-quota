import SwiftUI
import MobileAccessCore

@MainActor @Observable
final class MobileQuotaInsightModel {
    struct Query: Equatable {
        let profile: AccountProfile
        let reading: QuotaReading
    }
    struct RefreshID: Equatable {
        let queries: [Query]
        let minute: Int
    }
    struct Insight {
        let forecast: QuotaExhaustionForecast
        let query: Query
        var label: String {
            let name = query.profile.service.name
            let label = query.profile.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? name : label.localizedCaseInsensitiveContains(name) ? label : "\(label) \(name)"
        }
    }
    private var insight: Insight?
    private var dismissed: Set<QuotaForecastScope> = []

    static func queries(_ accounts: MobileAccountCollection) -> [Query] {
        accounts.profiles.compactMap { profile in
            let reading: QuotaReading?
            switch profile.service {
            case .codex:
                guard let model = accounts.codex(profile), !model.isDemo, model.connected,
                      model.error == nil, model.connectionFailure == nil else { return nil }
                reading = model.reading
            case .claude:
                guard let model = accounts.claude(profile), !model.isDemo, model.connected,
                      model.error == nil, model.connectionFailure == nil else { return nil }
                reading = model.reading
            }
            guard let reading, reading.providerIdentity != nil else { return nil }
            return Query(profile: profile, reading: reading)
        }
    }

    func current(queries: [Query], now: Date) -> Insight? {
        guard let insight, queries.contains(insight.query), !dismissed.contains(insight.forecast.scope),
              insight.forecast.earliest > now, insight.forecast.validUntil > now else { return nil }
        return insight
    }

    func refresh(queries: [Query], now: Date) async {
        var candidates: [Insight] = []
        for query in queries {
            let forecasts = (try? await SharedQuotaStore(query.profile).quotaForecasts(matching: query.reading, now: now)) ?? []
            candidates += forecasts.filter { !dismissed.contains($0.scope) }.map { Insight(forecast: $0, query: query) }
        }
        guard !Task.isCancelled else { return }
        insight = candidates.min { $0.forecast.earliest < $1.forecast.earliest }
    }

    func dismiss(_ value: Insight) {
        dismissed.insert(value.forecast.scope)
        insight = nil
        Task { try? await SharedQuotaStore(value.query.profile).dismissForecast(value.forecast.scope) }
    }
}

struct MobileQuotaInsightBanner: View {
    let forecast: QuotaExhaustionForecast
    let accountLabel: String
    var wide = false
    let dismiss: () -> Void

    var body: some View {
        OverviewAlerts(announcement: nil, forecast: forecast, accountLabel: accountLabel,
                       wide: wide, openDetails: {}, dismissAnnouncement: {}, dismissForecast: dismiss)
    }
}
