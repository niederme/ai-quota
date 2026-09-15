import Foundation
import CryptoKit
import Testing
@testable import MobileAccessCore

private struct ClaudeMock: HTTPTransport {
    let handler: @Sendable (URLRequest) throws -> HTTPResult
    func send(_ request: URLRequest) async throws -> HTTPResult { try handler(request) }
}
private let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
private func reply(_ body: String, status: Int = 200) -> HTTPResult {
    HTTPResult(data: Data(body.utf8), status: status)
}

@Test func claudeChallengeBindsStateAndPKCE() throws {
    let challenge = try ClaudeChallenge(now: timestamp)
    let second = try ClaudeChallenge(now: timestamp)
    #expect(challenge.state != second.state)
    #expect(challenge.verifier != second.verifier)
    let url = try #require(URLComponents(url: challenge.authorizationURL, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(url.host == "claude.ai")
    #expect(query["scope"] == "org:create_api_key user:profile")
    #expect(query["code_challenge_method"] == "S256")
    let expected = Data(SHA256.hash(data: Data(challenge.verifier.utf8))).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    #expect(query["code_challenge"] == expected)
    #expect(try challenge.code(from: " code#\(challenge.state)\n", now: timestamp) == "code")
    for invalid in ["code", "code#wrong", "#\(challenge.state)", "a b#\(challenge.state)"] {
        #expect(throws: (any Error).self) { try challenge.code(from: invalid, now: timestamp) }
    }
    #expect(throws: (any Error).self) {
        try challenge.code(from: "code#\(challenge.state)", now: timestamp.addingTimeInterval(901))
    }
}
@Test func claudeExchangeRejectsWrongStateBeforeNetwork() async throws {
    let api = ClaudeAPI(transport: ClaudeMock { _ in
        Issue.record("Invalid state must not reach the network")
        return reply("{}")
    })
    let challenge = try ClaudeChallenge(now: timestamp)
    await #expect(throws: (any Error).self) {
        try await api.exchange("code#wrong", challenge: challenge, now: timestamp)
    }
}
@Test func claudeExchangeUsesJSONAndDoesNotCreateKeys() async throws {
    let challenge = try ClaudeChallenge(now: timestamp)
    let api = ClaudeAPI(transport: ClaudeMock { request in
        #expect(request.url?.absoluteString == "https://console.anthropic.com/v1/oauth/token")
        #expect(request.httpMethod == "POST")
        let body = try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))
        #expect(body["code"] == "code")
        #expect(body["state"] == challenge.state)
        #expect(body["code_verifier"] == challenge.verifier)
        #expect(body["redirect_uri"] == ClaudeAPI.redirectURI)
        return reply(#"{"access_token":"synthetic","refresh_token":"refresh","expires_in":3600}"#)
    })
    let tokens = try await api.exchange("code#\(challenge.state)", challenge: challenge, now: timestamp)
    #expect(tokens.expiresAt == timestamp.addingTimeInterval(3600))
}
@Test func claudeRenewalKeepsOrRotatesRefreshToken() async throws {
    for rotated in [false, true] {
        let api = ClaudeAPI(transport: ClaudeMock { request in
            let body = try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))
            #expect(body["grant_type"] == "refresh_token")
            #expect(body["scope"] == nil)
            #expect(body["refresh_token"] == "original")
            #expect(body["client_id"] == ClaudeAPI.clientID)
            return reply(rotated
                ? #"{"access_token":"new","refresh_token":"rotated","expires_in":3600}"#
                : #"{"access_token":"new","expires_in":3600}"#)
        })
        let old = ClaudeTokens(accessToken: "old", refreshToken: "original", expiresAt: timestamp)
        let new = try await api.renew(old, now: timestamp)
        #expect(new.refreshToken == (rotated ? "rotated" : "original"))
        #expect(!new.needsRefresh(at: timestamp))
    }
}
@Test func claudeUsageSupportsBothDateFormsAndMissingWindows() throws {
    let data = Data(#"{"five_hour":{"utilization":12,"resets_at":"2027-01-15T12:00:00.123Z"},"seven_day":{"utilization":45,"resets_at":"2027-01-20T12:00:00Z"}}"#.utf8)
    let reading = try ClaudeAPI.decodeUsage(data, now: timestamp)
    #expect(reading.shortTerm?.usedPercent == 12)
    #expect(reading.weekly?.usedPercent == 45)
    #expect(reading.shortTerm?.resetsAt != nil)
    #expect(reading.weekly?.resetsAt != nil)
    let missing = try ClaudeAPI.decodeUsage(Data(#"{"five_hour":null,"seven_day":{"utilization":0}}"#.utf8), now: timestamp)
    #expect(missing.shortTerm == nil)
    #expect(missing.weekly?.usedPercent == 0)
}
@Test func claudeBadReadingsStayUnavailable() {
    for raw in [#"{}"#, #"{"five_hour":{"utilization":null}}"#,
                #"{"five_hour":{"utilization":101}}"#,
                #"{"five_hour":{"utilization":1,"resets_at":"invalid"}}"#] {
        #expect(throws: (any Error).self) { try ClaudeAPI.decodeUsage(Data(raw.utf8), now: timestamp) }
    }
}
@Test func claudeUsageHeadersAndFailureAreHonest() async throws {
    let api = ClaudeAPI(transport: ClaudeMock { request in
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "AIQuotaMobileProbe/0.1")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil)
        return reply("private provider body", status: 403)
    })
    let tokens = ClaudeTokens(accessToken: "synthetic", refreshToken: nil, expiresAt: timestamp)
    do {
        _ = try await api.usage(tokens)
        Issue.record("Expected failure")
    } catch let error as ClaudeAccessError {
        #expect(error.errorDescription?.contains("usage update") == true)
        #expect(error.errorDescription?.contains("403") == true)
        #expect(error.errorDescription?.contains("private provider body") == false)
    }
}


@Test func claudeRenewalFailureOffersSafeRecovery() async throws {
    let tokens = ClaudeTokens(accessToken: "old", refreshToken: "refresh", expiresAt: timestamp)
    for body in [#"{"error":"invalid_grant","error_description":"secret"}"#, #"{"error":"invalid_scope"}"#] {
        let api = ClaudeAPI(transport: ClaudeMock { _ in reply(body, status: 400) })
        do {
            _ = try await api.renew(tokens)
            Issue.record("Expected renewal failure")
        } catch let error as ClaudeAccessError {
            let message = error.errorDescription ?? ""
            #expect(!message.contains("secret"))
            if body.contains("invalid_grant") {
                #expect(message.contains("Reconnect Claude"))
            } else {
                #expect(message.contains("sign-in renewal"))
                #expect(message.contains("400"))
            }
        }
    }
}

@Test func renewalErrorsClassifyNestedCodesAndNeverExposeUnknownBodies() async throws {
    for (body, expected) in [
        (#"{"error":{"type":"invalid_grant","message":"secret-token"}}"#, "reconnect"),
        (#"{"error":{"type":"invalid_scope","message":"secret-token"}}"#, "invalid_scope"),
        (#"{"error":"secret-token","error_description":"private"}"#, "unknown")
    ] {
        let api = ClaudeAPI(transport: ClaudeMock { _ in reply(body, status: 400) })
        do {
            _ = try await api.renew(ClaudeTokens(accessToken: "test", refreshToken: "test-refresh", expiresAt: timestamp))
            Issue.record("Expected failure")
        } catch let error as ClaudeAccessError {
            #expect(!error.localizedDescription.contains("secret-token"))
            #expect(!error.localizedDescription.contains("private"))
            if expected == "reconnect" { #expect(error.requiresReconnect) }
            else {
                #expect(!error.requiresReconnect)
                guard case let .renewalRejected(status, reason) = error else { Issue.record("Expected renewal classification"); continue }
                #expect(status == 400)
                #expect(reason == (expected == "unknown" ? nil : expected))
            }
        }
    }
}


private actor ChangingClaudeProfile: HTTPTransport {
    var profileResponses: [HTTPResult]
    init(_ responses: [HTTPResult]) { profileResponses = responses }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic")
        if request.url?.path == "/api/oauth/usage" {
            return reply(#"{"five_hour":{"utilization":12},"seven_day":{"utilization":31},"extra_usage":{"used_credits":15.58,"currency":"USD"}}"#)
        }
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/profile")
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-cache")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.timeoutInterval <= 5)
        return profileResponses.removeFirst()
    }
}

@Test func claudePlanTracksUpgradesDowngradesAndUnavailableProfiles() async throws {
    let transport = ChangingClaudeProfile([
        reply(#"{"organization":{"organization_type":"claude_pro"}}"#),
        reply(#"{"organization":{"organization_type":"claude_max"}}"#),
        reply(#"{"organization":{"organization_type":"claude_pro"}}"#),
        reply("{}", status: 503),
        reply(#"{"organization":{"organization_type":"future_plan"}}"#),
        reply("malformed"),
        reply(#"{"organization":{"organization_type":"claude_team"}}"#)
    ])
    let api = ClaudeAPI(transport: transport)
    let tokens = ClaudeTokens(accessToken: "synthetic", refreshToken: nil, expiresAt: timestamp)
    for expected: String? in ["Pro", "Max", "Pro", nil, nil, nil, "Team"] {
        let reading = try await api.usage(tokens, now: timestamp)
        #expect(reading.metadata?.displayPlan == expected)
        #expect(reading.shortTerm?.usedPercent == 12)
        #expect(reading.metadata?.usageSpent == 15.58)
    }
}

@Test func claudeProfileNetworkFailureKeepsQuotaWithoutAPlanGuess() async throws {
    let api = ClaudeAPI(transport: ClaudeMock { request in
        if request.url?.path == "/api/oauth/profile" { throw URLError(.timedOut) }
        return reply(#"{"five_hour":{"utilization":8}}"#)
    })
    let reading = try await api.usage(ClaudeTokens(accessToken: "synthetic", refreshToken: nil, expiresAt: timestamp))
    #expect(reading.shortTerm?.usedPercent == 8)
    #expect(reading.metadata?.plan == nil)
}
