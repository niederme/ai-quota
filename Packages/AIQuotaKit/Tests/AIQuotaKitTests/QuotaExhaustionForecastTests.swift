import Foundation
import Testing
@testable import AIQuotaKit

private let paceNow = Date(timeIntervalSince1970: 1_800_000_000)
private func paceScope(_ window: QuotaForecastScope.Window = .weekly,
                       account: String = "personal", identity: String = "org-personal",
                       reset: Date = paceNow.addingTimeInterval(4 * 86400),
                       plan: String = "pro") -> QuotaForecastScope {
    .init(accountID: account, provider: "claude", identity: identity,
          source: "web", plan: plan, window: window, resetAt: reset)
}
private func paceSamples(_ scope: QuotaForecastScope, span: TimeInterval = 24 * 3600,
                         from: Double = 25, to: Double = 65, count: Int = 25,
                         end: Date = paceNow, limit: Double = 100) -> [QuotaPaceObservation] {
    (0..<count).map { i in
        let fraction = Double(i) / Double(count - 1)
        return .init(scope: scope, date: end.addingTimeInterval(-span * (1 - fraction)),
                     used: from + (to - from) * fraction, limit: limit)
    }
}

@Test func quotaForecastRequiresHistoryRatherThanCurrentPercent() {
    let scope = paceScope()
    #expect(QuotaExhaustionForecast.estimate(scope: scope,
        observations: [.init(scope: scope, date: paceNow, used: 51)], now: paceNow) == nil)
    #expect(QuotaExhaustionForecast.estimate(scope: scope,
        observations: paceSamples(scope, span: 11 * 3600), now: paceNow) == nil)
    #expect(QuotaExhaustionForecast.estimate(scope: scope,
        observations: paceSamples(scope, span: 12 * 3600, count: 6), now: paceNow) == nil)
}

@Test func quotaForecastUsesConservativeRoundedWindowBeforeReset() throws {
    let scope = paceScope()
    let forecast = try #require(QuotaExhaustionForecast.estimate(scope: scope,
        observations: paceSamples(scope), now: paceNow))
    #expect(forecast.earliest > paceNow)
    #expect(forecast.latest > forecast.earliest)
    #expect(forecast.latest < scope.resetAt)
    #expect(forecast.latest.timeIntervalSince(forecast.earliest) >= 6 * 3600)
    #expect(forecast.earliest.timeIntervalSince1970.truncatingRemainder(dividingBy: 6 * 3600) == 0)
}

@Test func quotaForecastEligibilityBoundaries() {
    let scope = paceScope()
    #expect(QuotaExhaustionForecast.estimate(scope: scope,
        observations: paceSamples(scope, span: 12 * 3600, count: 7), now: paceNow) != nil)
    #expect(QuotaExhaustionForecast.estimate(scope: scope,
        observations: paceSamples(scope, span: 12 * 3600 - 1, count: 7), now: paceNow) == nil)
    #expect(QuotaExhaustionForecast.estimate(scope: scope,
        observations: paceSamples(scope, from: 90, to: 95), now: paceNow) != nil)
    #expect(QuotaExhaustionForecast.estimate(scope: scope,
        observations: paceSamples(scope, from: 90, to: 94.99), now: paceNow) == nil)
    #expect(QuotaExhaustionForecast.estimate(scope: scope,
        observations: paceSamples(scope), now: paceNow.addingTimeInterval(3600)) != nil)
    #expect(QuotaExhaustionForecast.estimate(scope: scope,
        observations: paceSamples(scope), now: paceNow.addingTimeInterval(3601)) == nil)
}

@Test func quotaForecastNeverCombinesAccountsSourcesPlansOrWindows() {
    let personal = paceScope()
    for other in [paceScope(account: "work"), paceScope(identity: "other-org"),
                  paceScope(.monthly), paceScope(plan: "max"),
                  paceScope(reset: personal.resetAt.addingTimeInterval(3600)),
                  QuotaForecastScope(accountID: "personal", provider: "codex", identity: "org-personal",
                    source: "web", plan: "pro", window: .weekly, resetAt: personal.resetAt),
                  QuotaForecastScope(accountID: "personal", provider: "claude", identity: "org-personal",
                    source: "oauth", plan: "pro", window: .weekly, resetAt: personal.resetAt)] {
        #expect(QuotaExhaustionForecast.estimate(scope: personal,
            observations: paceSamples(other), now: paceNow) == nil)
    }
}

@Test func quotaForecastSuppressesStaleFutureEmptyZeroAndExhaustedReadings() {
    let scope = paceScope()
    for samples in [[], paceSamples(scope, from: 0, to: 0), paceSamples(scope, from: 100, to: 100),
                    paceSamples(scope, from: 65, to: 65), paceSamples(scope, end: paceNow.addingTimeInterval(-3601)),
                    paceSamples(scope, end: paceNow.addingTimeInterval(1)),
                    paceSamples(scope, from: .nan, to: .nan), paceSamples(scope, from: -10, to: 60)] {
        #expect(QuotaExhaustionForecast.estimate(scope: scope, observations: samples, now: paceNow) == nil)
    }
}

@Test func quotaForecastDoesNotProjectBeyondResetOrTooFarBeyondEvidence() {
    for scope in [paceScope(reset: paceNow.addingTimeInterval(20 * 3600)),
                  paceScope(reset: paceNow.addingTimeInterval(-1))] {
        #expect(QuotaExhaustionForecast.estimate(scope: scope,
            observations: paceSamples(scope), now: paceNow) == nil)
    }
    let scope = paceScope()
    #expect(QuotaExhaustionForecast.estimate(scope: scope,
        observations: paceSamples(scope, from: 10, to: 20), now: paceNow) == nil)
}

@Test func quotaForecastRejectsBurstsIdleAndAbruptRateChanges() {
    let scope = paceScope()
    let base = paceSamples(scope)
    let burst: [Double] = (0..<25).map { $0 < 23 ? 25.0 : 65.0 }
    let idle: [Double] = (0..<25).map { $0 < 12 ? 25.0 + Double($0) * 3.0 : 61.0 }
    let faster: [Double] = (0..<25).map { i in
        if i < 12 { return 25.0 + Double(i) / 2.0 }
        return 31.0 + Double(i - 12) * 3.0
    }
    let slower: [Double] = (0..<25).map { i in
        if i < 12 { return 25.0 + Double(i) * 3.0 }
        return 61.0 + Double(i - 12) / 4.0
    }
    let patterns = [burst, idle, faster, slower]
    for values in patterns {
        let samples = zip(base, values).map { QuotaPaceObservation(scope: scope, date: $0.date, used: $1) }
        #expect(QuotaExhaustionForecast.estimate(scope: scope, observations: samples, now: paceNow) == nil)
    }
}

@Test func quotaForecastRestartsAfterDropGapOrChangedCapacity() {
    let scope = paceScope()
    var samples = paceSamples(scope)
    samples.append(.init(scope: scope, date: paceNow.addingTimeInterval(60), used: 5))
    #expect(QuotaExhaustionForecast.estimate(scope: scope, observations: samples,
        now: paceNow.addingTimeInterval(60)) == nil)
    samples = paceSamples(scope)
    samples.append(.init(scope: scope, date: paceNow.addingTimeInterval(60), used: 66, limit: 200))
    #expect(QuotaExhaustionForecast.estimate(scope: scope, observations: samples,
        now: paceNow.addingTimeInterval(60)) == nil)
    samples = paceSamples(scope, count: 7) // each gap is 4h, exactly allowed
    #expect(QuotaExhaustionForecast.estimate(scope: scope, observations: samples, now: paceNow) != nil)
    samples.remove(at: 5) // 8h gap before the current reading
    #expect(QuotaExhaustionForecast.estimate(scope: scope, observations: samples, now: paceNow) == nil)
}

@Test func quotaForecastSeparatesFiveHourAndMonthlyPolicies() {
    let hourly = paceScope(.fiveHour, reset: paceNow.addingTimeInterval(3 * 3600))
    #expect(QuotaExhaustionForecast.estimate(scope: hourly,
        observations: paceSamples(hourly, span: 3600, from: 15, to: 50, count: 13), now: paceNow) != nil)
    let monthly = paceScope(.monthly, reset: paceNow.addingTimeInterval(10 * 86400))
    #expect(QuotaExhaustionForecast.estimate(scope: monthly,
        observations: paceSamples(monthly, span: 2 * 86400, from: 250, to: 650, limit: 1000), now: paceNow) != nil)
    #expect(QuotaExhaustionForecast.estimate(scope: monthly,
        observations: paceSamples(monthly, span: 23 * 3600), now: paceNow) == nil)
}

@Test func quotaForecastIgnoresPollingFrequencyAndDuplicateReads() {
    let scope = paceScope()
    let regular = paceSamples(scope)
    let dense = paceSamples(scope, count: 193)
    #expect(QuotaExhaustionForecast.estimate(scope: scope, observations: regular, now: paceNow)
        == QuotaExhaustionForecast.estimate(scope: scope, observations: dense + dense, now: paceNow))
}

@Test func quotaInsightStorePersistsDismissalAndScopesNewWindows() async throws {
    let suite = "QuotaInsightTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = QuotaInsightStore(suiteName: suite)
    let scope = paceScope()
    for sample in paceSamples(scope) { await store.record(sample, now: sample.date) }
    #expect(await store.forecasts(accountID: "personal", provider: "claude", identity: "org-personal",
        source: "web", plan: "pro", now: paceNow).count == 1)
    #expect(await store.forecasts(accountID: "work", provider: "claude", identity: "org-personal",
        source: "web", plan: "pro", now: paceNow).isEmpty)
    await store.dismiss(scope)
    let reloaded = QuotaInsightStore(suiteName: suite)
    #expect(await reloaded.forecasts(accountID: "personal", provider: "claude", identity: "org-personal",
        source: "web", plan: "pro", now: paceNow).isEmpty)
    let newPlan = paceScope(plan: "max")
    for sample in paceSamples(newPlan) { await reloaded.record(sample, now: sample.date) }
    #expect(await reloaded.forecasts(accountID: "personal", provider: "claude", identity: "org-personal",
        source: "web", plan: "max", now: paceNow).isEmpty)
    let newReset = paceScope(reset: scope.resetAt.addingTimeInterval(86400))
    for sample in paceSamples(newReset) { await reloaded.record(sample, now: sample.date) }
    #expect(await reloaded.forecasts(accountID: "personal", provider: "claude", identity: "org-personal",
        source: "web", plan: "pro", now: paceNow).count == 1)
}

@Test func quotaInsightStoreRejectsUnverifiedClaudeAndMissingReset() async throws {
    let suite = "QuotaInsightTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = ConnectedAccount(provider: .claude, displayLabel: "Personal", workspaceID: "org-personal", authSource: .webSession)
    let store = QuotaInsightStore(suiteName: suite, accountLookup: { $0 == account.id ? account : nil })
    for source in [ClaudeUsage.Source.oauth, .unknown, .web] {
        for sample in paceSamples(paceScope()) {
            let usage = ClaudeUsage(fiveHourUtilization: nil, fiveHourResetsAt: nil,
                sevenDayUtilization: sample.used, sevenDayResetsAt: source == .web ? nil : sample.scope.resetAt,
                extraUsage: nil, source: source, fetchedAt: sample.date)
            await store.recordClaude(usage, account: account, identity: "org-personal", now: sample.date)
            await store.recordClaude(usage, account: account, identity: "org-work", now: sample.date)
        }
    }
    #expect(await store.forecasts(accountID: account.id, provider: "claude", identity: "org-personal",
        source: "web", plan: "pro", now: paceNow).isEmpty)
}

@Test func quotaInsightStoreCapturesOnlyMatchingFreshWebWindow() async throws {
    let suite = "QuotaInsightTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = ConnectedAccount(provider: .claude, displayLabel: "Personal", workspaceID: "org-personal", authSource: .webSession)
    let store = QuotaInsightStore(suiteName: suite, accountLookup: { $0 == account.id ? account : nil })
    let scope = paceScope()
    for sample in paceSamples(scope) {
        let usage = ClaudeUsage(fiveHourUtilization: nil, fiveHourResetsAt: nil,
            sevenDayUtilization: sample.used, sevenDayResetsAt: sample.scope.resetAt,
            extraUsage: nil, source: .web, fetchedAt: sample.date, quotaScopeID: "org-personal")
        await store.recordClaude(usage, account: account, identity: "org-personal", now: sample.date)
    }
    let forecasts = await store.forecasts(accountID: account.id, provider: "claude", identity: "org-personal",
        source: "web", plan: "pro", now: paceNow)
    #expect(forecasts.count == 1)
    #expect(forecasts.first?.scope.window == .weekly)
    #expect(await store.forecasts(accountID: account.id, provider: "claude", identity: "org-work",
        source: "web", plan: "pro", now: paceNow).isEmpty)
    // A corrected current reading invalidates the old pace without editing the
    // user's usage cache or keeping a forecast based on pre-correction samples.
    let corrected = ClaudeUsage(fiveHourUtilization: nil, fiveHourResetsAt: nil,
        sevenDayUtilization: 0, sevenDayResetsAt: scope.resetAt, extraUsage: nil,
        source: .web, fetchedAt: paceNow.addingTimeInterval(1), quotaScopeID: "org-personal")
    await store.recordClaude(corrected, account: account, identity: "org-personal", now: corrected.fetchedAt)
    #expect(await store.forecasts(accountID: account.id, provider: "claude", identity: "org-personal",
        source: "web", plan: "pro", now: corrected.fetchedAt).isEmpty)
}

@Test func quotaInsightStoreRejectsReplayAndFutureSamples() async throws {
    let suite = "QuotaInsightTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = QuotaInsightStore(suiteName: suite)
    let scope = paceScope()
    // Replaying past samples at launch cannot backfill a pace series.
    for sample in paceSamples(scope) { await store.record(sample, now: paceNow) }
    for sample in paceSamples(scope, end: paceNow.addingTimeInterval(86400)) {
        await store.record(sample, now: paceNow)
    }
    #expect(await store.forecasts(accountID: "personal", provider: "claude", identity: "org-personal",
        source: "web", plan: "pro", now: paceNow).isEmpty)
}

private func codexPaceUsage(_ sample: QuotaPaceObservation,
                            shape: CodexUsage.ReportedWindowShape? = .weeklyOnly,
                            identity: String? = "codex-work", source: CodexAuthSource? = .codexOAuth,
                            shortDuration: Int = 18000) -> CodexUsage {
    CodexUsage(weeklyUsedPercent: Int(sample.used), weeklyResetAt: sample.scope.resetAt,
        weeklyResetAfterSeconds: 0, hourlyUsedPercent: Int(sample.used), hourlyResetAt: sample.scope.resetAt,
        hourlyResetAfterSeconds: 0, hourlyWindowSeconds: shortDuration, limitReached: false,
        allowed: true, planType: "business", creditBalance: nil, approxLocalMessages: nil,
        approxCloudMessages: nil, fetchedAt: sample.date,
        monthlyBudget: shape == nil ? .init(unit: "credit", used: sample.used, limit: sample.limit,
                                            resetAt: sample.scope.resetAt) : nil,
        reportedWindowShape: shape, accountID: identity, quotaSource: source)
}

@Test func quotaInsightCodexCaptureSupportsVerifiedWeeklyAndExplicitMonthlyWindows() async throws {
    for window in [QuotaForecastScope.Window.weekly, .monthly] {
        let suite = "QuotaInsightTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = ConnectedAccount(provider: .codex, displayLabel: "Work", workspaceID: "codex-work", authSource: .oauth)
        let store = QuotaInsightStore(suiteName: suite, accountLookup: { $0 == account.id ? account : nil })
        let reset = paceNow.addingTimeInterval(window == .monthly ? 10 * 86400 : 4 * 86400)
        let scope = QuotaForecastScope(accountID: account.id, provider: "codex", identity: "codex-work",
            source: "codexOAuth", plan: "business", window: window, resetAt: reset)
        let samples = paceSamples(scope, span: window == .monthly ? 2 * 86400 : 86400,
                                  from: 25, to: 65)
        for sample in samples {
            let usage = codexPaceUsage(sample, shape: window == .monthly ? nil : .weeklyOnly)
            await store.recordCodex(usage, account: account, identity: "codex-work", now: sample.date)
        }
        let forecasts = await store.forecasts(accountID: account.id, provider: "codex", identity: "codex-work",
            source: "codexOAuth", plan: "business", now: paceNow)
        #expect(forecasts.count == 1)
        #expect(forecasts.first?.scope.window == window)
        #expect(await store.forecasts(accountID: account.id, provider: "codex", identity: "other-workspace",
            source: "codexOAuth", plan: "business", now: paceNow).isEmpty)
    }
}

@Test func quotaInsightCodexRejectsUnknownIdentitySourceAndNonFiveHourDuration() async throws {
    let suite = "QuotaInsightTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = ConnectedAccount(provider: .codex, displayLabel: "Work", workspaceID: "codex-work", authSource: .oauth)
    let store = QuotaInsightStore(suiteName: suite, accountLookup: { $0 == account.id ? account : nil })
    let scope = QuotaForecastScope(accountID: account.id, provider: "codex", identity: "codex-work",
        source: "codexOAuth", plan: "business", window: .fiveHour, resetAt: paceNow.addingTimeInterval(4 * 3600))
    for sample in paceSamples(scope, span: 3600, from: 15, to: 50, count: 13) {
        for usage in [codexPaceUsage(sample, shape: .dual, identity: nil),
                      codexPaceUsage(sample, shape: .dual, identity: "personal"),
                      codexPaceUsage(sample, shape: .dual, source: nil),
                      codexPaceUsage(sample, shape: .dual, source: .unknown),
                      codexPaceUsage(sample, shape: .dual, shortDuration: 3600)] {
            await store.recordCodex(usage, account: account, identity: "codex-work", now: sample.date)
        }
    }
    #expect(await store.forecasts(accountID: account.id, provider: "codex", identity: "codex-work",
        source: "codexOAuth", plan: "business", now: paceNow).isEmpty)
    for sample in paceSamples(scope, span: 3600, from: 15, to: 50, count: 13) {
        await store.recordCodex(codexPaceUsage(sample, shape: .dual), account: account,
                               identity: "codex-work", now: sample.date)
    }
    let forecast = try #require(await store.forecasts(accountID: account.id, provider: "codex", identity: "codex-work",
        source: "codexOAuth", plan: "business", now: paceNow).first)
    #expect(forecast.scope.window == .fiveHour)
    #expect(forecast.validUntil <= paceNow.addingTimeInterval(20 * 60))
}

@Test func quotaInsightResetAndRemovalRejectLateCapturesAndPersistEmptyState() async throws {
    let suite = "QuotaInsightTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = ConnectedAccount(provider: .codex, displayLabel: "Work", workspaceID: "codex-work", authSource: .oauth)
    let registered = LockIsolated<ConnectedAccount?>(account)
    let store = QuotaInsightStore(suiteName: suite, accountLookup: { _ in registered.value })
    let generation = await store.captureGeneration()
    let scope = QuotaForecastScope(accountID: account.id, provider: "codex", identity: "codex-work",
        source: "codexOAuth", plan: "business", window: .weekly, resetAt: paceNow.addingTimeInterval(4 * 86400))
    for sample in paceSamples(scope) {
        await store.recordCodex(codexPaceUsage(sample), account: account, identity: "codex-work",
                               now: sample.date, captureGeneration: generation)
    }
    #expect(await store.forecasts(accountID: account.id, provider: "codex", identity: "codex-work",
        source: "codexOAuth", plan: "business", now: paceNow).count == 1)
    await store.clear()
    // An already completed network request queued before reset cannot backfill.
    for sample in paceSamples(scope) {
        await store.recordCodex(codexPaceUsage(sample), account: account, identity: "codex-work",
                               now: sample.date, captureGeneration: generation)
    }
    registered.withLock { $0 = nil }
    for sample in paceSamples(scope) {
        await store.recordCodex(codexPaceUsage(sample), account: account, identity: "codex-work", now: sample.date)
    }
    let reloaded = QuotaInsightStore(suiteName: suite, accountLookup: { _ in registered.value })
    #expect(await reloaded.forecasts(accountID: account.id, provider: "codex", identity: "codex-work",
        source: "codexOAuth", plan: "business", now: paceNow).isEmpty)
}
