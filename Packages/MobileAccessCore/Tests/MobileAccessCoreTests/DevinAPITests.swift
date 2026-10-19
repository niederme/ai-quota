import Foundation
import Testing
@testable import MobileAccessCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

/// Mirrors the verified GetUserStatus response (identity fields redacted).
private func sampleJSON(
    dailyRemaining: Any = 100,
    weeklyRemaining: Any = 100,
    dailyReset: Any = "1792483200",
    weeklyReset: Any = "1792915200",
    overageMicros: Any = "\"35766036\"",
    promptCredits: Any = -1
) -> Data {
    Data("""
    {
        "userStatus": {
            "planStatus": {
                "planInfo": {
                    "planName": "Pro",
                    "billingStrategy": "BILLING_STRATEGY_QUOTA",
                    "devinInfo": {
                        "accountDisplayName": "example - Personal",
                        "orgId": "org-redacted"
                    }
                },
                "planStart": "2026-10-13T15:00:58Z",
                "planEnd": "2026-11-13T15:00:58Z",
                "availablePromptCredits": \(promptCredits),
                "dailyQuotaRemainingPercent": \(dailyRemaining),
                "weeklyQuotaRemainingPercent": \(weeklyRemaining),
                "overageBalanceMicros": \(overageMicros),
                "dailyQuotaResetAtUnix": "\(dailyReset)",
                "weeklyQuotaResetAtUnix": "\(weeklyReset)"
            }
        },
        "planInfo": {}
    }
    """.utf8)
}

@Test func devinRequestIsConnectRPCJSON() throws {
    let request = DevinAPI.userStatusRequest(
        apiServerURL: URL(string: "https://server.codeium.com")!,
        apiKey: "devin-session-token$abc"
    )
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://server.codeium.com/exa.seat_management_pb.SeatManagementService/GetUserStatus")
    #expect(request.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
    let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
    let metadata = try #require(body?["metadata"] as? [String: Any])
    #expect(metadata["apiKey"] as? String == "devin-session-token$abc")
    #expect(metadata["ideName"] as? String == "devin")
}

@Test func devinDecodeFlipsRemainingToUsed() throws {
    let usage = try DevinAPI.decodeUserStatus(
        sampleJSON(dailyRemaining: 40, weeklyRemaining: 15),
        now: now, source: .cli
    )
    #expect(usage.dailyUsedPercent == 60)
    #expect(usage.weeklyUsedPercent == 85)
    #expect(usage.source == .cli)
    #expect(usage.fetchedAt == now)
}

@Test func devinDecodeParsesResetsPlanAndBalance() throws {
    let usage = try DevinAPI.decodeUserStatus(sampleJSON(), now: now, source: .appState)
    #expect(usage.dailyResetsAt == Date(timeIntervalSince1970: 1_792_483_200))
    #expect(usage.weeklyResetsAt == Date(timeIntervalSince1970: 1_792_915_200))
    #expect(usage.planName == "Pro")
    #expect(usage.accountDisplayName == "example - Personal")
    #expect(usage.overageBalanceUSD == 35.766036)
    #expect(usage.planStart != nil)
    #expect(usage.planEnd != nil)
    #expect(usage.limitReached == false)
}

@Test func devinDecodeAcceptsNumericStringsAndNumbers() throws {
    // overageBalanceMicros arrives as a string; reset times as quoted unix seconds.
    let usage = try DevinAPI.decodeUserStatus(sampleJSON(overageMicros: 1500000), now: now, source: .cli)
    #expect(usage.overageBalanceUSD == 1.5)
}

@Test func devinDecodeClampsOutOfRangePercentages() throws {
    // >100% remaining clamps to 0% used; 0% remaining is 100% used.
    let usage = try DevinAPI.decodeUserStatus(
        sampleJSON(dailyRemaining: 150, weeklyRemaining: 0),
        now: now, source: .cli
    )
    #expect(usage.dailyUsedPercent == 0)
    #expect(usage.weeklyUsedPercent == 100)
    #expect(usage.limitReached == false)  // primary metric is the daily window
}

@Test func devinDecodeAllowsMissingOptionalMetadata() throws {
    let data = Data("""
    {"userStatus": {"planStatus": {
        "dailyQuotaRemainingPercent": 30,
        "dailyQuotaResetAtUnix": "1792483200"
    }}}
    """.utf8)
    let usage = try DevinAPI.decodeUserStatus(data, now: now, source: .cli)
    #expect(usage.dailyUsedPercent == 70)
    #expect(usage.weeklyUsedPercent == nil)
    #expect(usage.planName == nil)
    #expect(usage.overageBalanceUSD == nil)
}

@Test func devinDecodeRejectsMissingPlanStatusOrWindows() throws {
    #expect(throws: DevinAccessError.self) {
        try DevinAPI.decodeUserStatus(Data("{}".utf8), now: now, source: .cli)
    }
    #expect(throws: DevinAccessError.self) {
        try DevinAPI.decodeUserStatus(
            Data("""
            {"userStatus": {"planStatus": {"planInfo": {"planName": "Pro"}}}}
            """.utf8),
            now: now, source: .cli
        )
    }
    #expect(throws: (any Error).self) {
        try DevinAPI.decodeUserStatus(Data("not json".utf8), now: now, source: .cli)
    }
}

@Test func devinPromptCreditsSentinelDoesNotBreakDecode() throws {
    // availablePromptCredits == -1 is Devin's "unlimited" sentinel; decode must
    // tolerate it and must not surface it as a negative balance.
    let usage = try DevinAPI.decodeUserStatus(sampleJSON(promptCredits: -1), now: now, source: .cli)
    #expect(usage.dailyUsedPercent == 0)
    #expect(usage.overageBalanceUSD == 35.766036)
}

@Test func devinUsageComputedProperties() {
    // resetAfterSeconds is computed against the real clock, so compare loosely.
    let usage = DevinUsage(
        dailyUsedPercent: 55, dailyResetsAt: Date.now.addingTimeInterval(3600),
        weeklyUsedPercent: 90, weeklyResetsAt: Date.now.addingTimeInterval(100_000),
        planName: "Pro", accountDisplayName: nil, overageBalanceUSD: nil,
        planStart: nil, planEnd: nil, source: .cli, fetchedAt: Date.now
    )
    #expect(usage.usedPercent == 55)
    #expect(usage.resetAfterSeconds == 3600 || usage.resetAfterSeconds == 3599)
    #expect(usage.weeklyResetAfterSeconds == 100_000 || usage.weeklyResetAfterSeconds == 99_999)
    #expect(usage.limitReached == false)
    #expect(usage.planDisplayName == "Pro")
    #expect(usage.primaryMetricLabel == "1d")
}

@Test func devinMakeReadingMapsWindows() throws {
    let usage = try DevinAPI.decodeUserStatus(
        sampleJSON(dailyRemaining: 40, weeklyRemaining: 15), now: now, source: .cli
    )
    let reading = DevinAPI.makeReading(from: usage)
    #expect(reading.shortTerm?.usedPercent == 60)
    #expect(reading.weekly?.usedPercent == 85)
    #expect(reading.metadata?.plan == "Pro")
    #expect(reading.metadata?.balanceUSD == 35.766036)
    #expect(reading.fetchedAt == now)
}
