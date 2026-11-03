import Foundation
import Testing
@testable import MobileAccessCore

private let resetNow = Date(timeIntervalSince1970: 1_800_000_000)
private func resetForecast(account: String = "pro", identity: String = "workspace-pro", provider: String = "codex", window: QuotaForecastScope.Window = .weekly) -> QuotaExhaustionForecast {
    .init(scope: .init(accountID: account, provider: provider, identity: identity, source: "wham", plan: "pro",
                      window: window, resetAt: resetNow.addingTimeInterval(86400)),
          basis: .periodAverage, projectedUsedPercent: 140, validUntil: resetNow.addingTimeInterval(3600))
}
private func resetContext(_ count: Int?, account: String = "pro", identity: String = "workspace-pro", age: TimeInterval = 0) -> CodexBankedResetContext {
    .init(accountID: account, providerIdentity: identity, credits: .init(availableCount: count), fetchedAt: resetNow.addingTimeInterval(-age))
}
private func resetPayload(_ metadata: String = "") -> Data {
    Data("""
    {"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":73,"limit_window_seconds":604800,"reset_at":1800086400}}\(metadata)}
    """.utf8)
}

@Test func resetCreditDecodingDistinguishesUnknownZeroAndPositive() throws {
    for strategy in [JSONDecoder.KeyDecodingStrategy.useDefaultKeys, .convertFromSnakeCase] {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = strategy
        for (raw, count) in [("{}", nil), ("null", nil), ("false", nil), ("[]", nil),
                             (#"{"available_count":0}"#, 0), (#"{"available_count":1,"applicable_available_count":0}"#, 1),
                             (#"{"available_count":3,"applicable_available_count":2}"#, 3),
                             (#"{"available_count":-1}"#, nil), (#"{"available_count":1.5}"#, nil),
                             (#"{"available_count":"1"}"#, nil), (#"{"available_count":true}"#, nil),
                             (#"{"available_count":0,"applicable_available_count":1}"#, nil)] as [(String, Int?)] {
            let value = try decoder.decode(CodexResetCredits.self, from: Data(raw.utf8))
            #expect(value.availableCount == count)
        }
    }
    let reading = try QuotaReading.decode(resetPayload(), now: resetNow)
    #expect(reading.resetCredits == nil)
    for raw in ["null", "false", "[]", #"{"available_count":"bad"}"#] {
        let value = try QuotaReading.decode(resetPayload(",\"rate_limit_reset_credits\":\(raw)"), now: resetNow)
        #expect(value.resetCredits?.availableCount == nil)
        #expect(value.weekly?.usedPercent == 73)
    }
}

@Test func resetCreditsRoundTripAndMissingRefreshCannotResurrectOldBalance() throws {
    let data = resetPayload(#", "rate_limit_reset_credits":{"available_count":2,"applicable_available_count":0}"#)
    let reading = try QuotaReading.decode(data, now: resetNow).identifying("workspace-pro")
    #expect(reading.resetCredits?.availableCount == 2)
    #expect(reading.resetCredits?.applicableAvailableCount == 0)
    #expect(try JSONDecoder().decode(QuotaReading.self, from: JSONEncoder().encode(reading)) == reading)
    let freshMissing = try QuotaReading.decode(resetPayload(), now: resetNow.addingTimeInterval(1)).identifying("workspace-pro")
    #expect(freshMissing.resetCredits == nil)
    var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(reading)) as? [String: Any])
    old.removeValue(forKey: "resetCredits")
    let legacy = try JSONDecoder().decode(QuotaReading.self, from: JSONSerialization.data(withJSONObject: old))
    #expect(legacy.resetCredits == nil)
    #expect(!reading.accessibilitySummary.contains("reset available")) // No lock-screen/widget disclosure added.
}

@Test func bankedContextRequiresMatchingAccountProviderIdentityWindowAndFreshness() {
    let forecast = resetForecast()
    #expect(resetContext(1).availableCount(for: forecast, now: resetNow) == 1)
    #expect(resetContext(0).availableCount(for: forecast, now: resetNow) == 0)
    for context in [resetContext(nil), resetContext(2, account: "business"), resetContext(2, identity: "workspace-business"),
                    resetContext(2, age: 301), resetContext(2, age: -1), resetContext(2, account: ""), resetContext(2, identity: "")] {
        #expect(context.availableCount(for: forecast, now: resetNow) == nil)
    }
    #expect(resetContext(2, age: 300).availableCount(for: forecast, now: resetNow) == 2)
    #expect(resetContext(1).availableCount(for: resetForecast(provider: "claude"), now: resetNow) == nil)
    #expect(resetContext(1).availableCount(for: resetForecast(window: .fiveHour), now: resetNow) == nil)
    #expect(resetContext(1).availableCount(for: resetForecast(window: .monthly), now: resetNow) == nil)
    #expect(resetContext(1).availableCount(for: forecast, now: resetNow.addingTimeInterval(3600)) == nil)
    let business = resetForecast(account: "business", identity: "workspace-business")
    #expect(resetContext(2, account: "business", identity: "workspace-business").availableCount(for: business, now: resetNow) == 2)
    #expect(resetContext(1).availableCount(for: business, now: resetNow) == nil)
}

@Test func bankedCopyKeepsScheduledResetAndDoesNotChangeForecastOrPrivacyLabel() {
    let forecast = resetForecast()
    #expect(QuotaForecastTextFormatter.title(forecast, accountLabel: "Codex Pro") == "Codex Pro • may hit its weekly limit.")
    #expect(QuotaForecastTextFormatter.title(forecast, accountLabel: "Codex") == "Codex • may hit its weekly limit.")
    for (count, phrase) in [(0, "You have no banked resets available"), (1, "You have 1 banked reset available"), (2, "You have 2 banked resets available")] {
        let text = QuotaForecastTextFormatter.detail(forecast, bankedResets: resetContext(count), now: resetNow, locale: Locale(identifier: "en_US"))
        #expect(text.hasPrefix(phrase + " • Resets "))
        #expect(text.contains(QuotaForecastTextFormatter.reset(forecast, now: resetNow, locale: Locale(identifier: "en_US"))))
        #expect(!text.contains("workspace") && !text.contains("automatically"))
    }
    let unknown = QuotaForecastTextFormatter.detail(forecast, now: resetNow)
    #expect(!unknown.contains("banked"))
    #expect(QuotaForecastTextFormatter.detail(forecast, bankedResets: resetContext(1, age: 301), now: resetNow) == unknown)
    #expect(forecast.projectedUsedPercent == 140)
}

private struct ResetTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResult {
        #expect(request.httpMethod == nil || request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "workspace-pro")
        switch request.url?.path {
        case "/backend-api/wham/usage": return HTTPResult(data: resetPayload(#", "rate_limit_reset_credits":{"available_count":1}"#), status: 200)
        case "/backend-api/wham/usage/credit-usage-events": return HTTPResult(data: Data("{\"data\":[]}".utf8), status: 200)
        default: Issue.record("Unexpected request: reset feature must not redeem or purchase"); return HTTPResult(data: Data(), status: 500)
        }
    }
}
@Test func bankedMetadataSurvivesExistingUsageEnrichmentWithoutExtraRequests() async throws {
    let api = CodexAPI(transport: ResetTransport())
    let tokens = CodexTokens(accessToken: "synthetic", refreshToken: nil, accountID: "workspace-pro", expiresAt: resetNow.addingTimeInterval(3600))
    let reading = try await api.usage(tokens, now: resetNow, includeSpending: true)
    #expect(reading.resetCredits?.availableCount == 1)
    #expect(reading.metadata?.usageSpent == 0)
    #expect(reading.providerIdentity == "workspace-pro")
}

@Test func anExplicitlyDifferentResponseIdentityCannotSupplyResetEntitlement() async throws {
    struct Mismatched: HTTPTransport {
        func send(_ request: URLRequest) async throws -> HTTPResult {
            #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "workspace-pro")
            let data = resetPayload(#", "account_id":"workspace-business", "rate_limit_reset_credits":{"available_count":4}"#)
            return HTTPResult(data: data, status: 200)
        }
    }
    let api = CodexAPI(transport: Mismatched())
    let tokens = CodexTokens(accessToken: "synthetic", refreshToken: nil, accountID: "workspace-pro", expiresAt: resetNow)
    let reading = try await api.usage(tokens, now: resetNow)
    #expect(reading.providerIdentity == "workspace-pro")
    #expect(reading.resetCredits == nil)
}
