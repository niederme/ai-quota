import Foundation
import Testing
@testable import MobileAccessCore

private struct MockTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) throws -> HTTPResult
    func send(_ request: URLRequest) async throws -> HTTPResult { try handler(request) }
}
private func result(_ json: String, status: Int = 200) -> HTTPResult {
    HTTPResult(data: Data(json.utf8), status: status)
}
private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func missingWindowIsNotZero() throws {
    let reading = try QuotaReading.decode(Data(#"{"rate_limit":{"primary_window":{"used_percent":32,"limit_window_seconds":604800,"reset_at":1800500000}}}"#.utf8), now: now)
    #expect(reading.shortTerm == nil)
    #expect(reading.weekly?.usedPercent == 32)
}
@Test func twoWindowsAndMissingReset() throws {
    let reading = try QuotaReading.decode(Data(#"{"rate_limit":{"primary_window":{"used_percent":12.5,"limit_window_seconds":18000},"secondary_window":{"used_percent":80,"limit_window_seconds":604800,"reset_at":1800500000}}}"#.utf8), now: now)
    #expect(reading.shortTerm?.usedPercent == 12.5)
    #expect(reading.shortTerm?.resetsAt == nil)
    #expect(reading.weekly?.resetsAt == Date(timeIntervalSince1970: 1800500000))
}
@Test func emptyAndInvalidResponsesDoNotProduceReadings() {
    #expect(throws: AccessError.noWindows) { try QuotaReading.decode(Data(#"{"rate_limit":{}}"#.utf8), now: now) }
    #expect(throws: AccessError.invalidResponse) {
        try QuotaReading.decode(Data(#"{"rate_limit":{"primary_window":{"used_percent":-2,"limit_window_seconds":18000}}}"#.utf8), now: now)
    }
    #expect(throws: (any Error).self) { try QuotaReading.decode(Data("<html>sign in</html>".utf8), now: now) }
}
@Test func challengeAcceptsBothIntervalRepresentations() throws {
    for interval in ["\"5\"", "5", "0"] {
        let data = Data("{\"device_auth_id\":\"test\",\"usercode\":\"TEST-CODE\",\"interval\":\(interval)}".utf8)
        let challenge = try JSONDecoder().decode(DeviceChallenge.self, from: data)
        #expect(challenge.interval == 5)
        #expect(challenge.verificationURL.host == "auth.openai.com")
    }
}
@Test func challengeAndPendingPollContract() async throws {
    let api = CodexAPI(transport: MockTransport { request in
        if request.url?.path.hasSuffix("usercode") == true {
            #expect(request.httpMethod == "POST")
            let body = try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))
            #expect(body["client_id"] == CodexAPI.clientID)
            return result(#"{"device_auth_id":"test","user_code":"TEST-CODE","interval":"5"}"#)
        }
        return result("{}", status: 403)
    })
    let challenge = try await api.requestChallenge()
    #expect(try await api.poll(challenge) == nil)
}
@Test func tokenExchangeEscapesCodeAndDoesNotCreateAPIKeys() async throws {
    let api = CodexAPI(transport: MockTransport { request in
        #expect(request.url?.absoluteString == "https://auth.openai.com/oauth/token")
        let body = String(data: request.httpBody!, encoding: .utf8)!
        #expect(body.contains("code=abc%2B%26%3D"))
        #expect(body.contains("code_verifier=verifier"))
        #expect(!body.contains("api_key"))
        return result(#"{"access_token":"test-access","refresh_token":"test-refresh","expires_in":3600}"#)
    })
    let code = try JSONDecoder().decode(AuthorizationCode.self, from: Data(#"{"authorization_code":"abc+&=","code_verifier":"verifier"}"#.utf8))
    let tokens = try await api.exchange(code, now: now)
    #expect(tokens.expiresAt == now.addingTimeInterval(3600))
}
@Test func renewalRetainsRefreshTokenIfNotRotated() async throws {
    let api = CodexAPI(transport: MockTransport { request in
        #expect(String(data: request.httpBody!, encoding: .utf8)!.contains("grant_type=refresh_token"))
        return result(#"{"access_token":"new-access","expires_in":3600}"#)
    })
    let old = CodexTokens(accessToken: "old", refreshToken: "refresh", accountID: "account", expiresAt: now)
    let updated = try await api.renew(old, now: now)
    #expect(updated.refreshToken == "refresh")
    #expect(updated.accountID == "account")
}
@Test func usageSendsAuthOnlyToUsageEndpoint() async throws {
    let api = CodexAPI(transport: MockTransport { request in
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "account")
        #expect(request.httpBody == nil)
        return result(#"{"rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":18000}}}"#)
    })
    let tokens = CodexTokens(accessToken: "test", refreshToken: nil, accountID: "account", expiresAt: now)
    let reading = try await api.usage(tokens, now: now)
    #expect(reading.fetchedAt == now)
    #expect(reading.shortTerm?.usedPercent == 0)
    #expect(reading.weekly == nil)
}
@Test func providerErrorsNeverBecomeZeroUsage() async throws {
    let api = CodexAPI(transport: MockTransport { _ in result("sensitive provider body", status: 401) })
    let tokens = CodexTokens(accessToken: "test", refreshToken: nil, accountID: nil, expiresAt: now)
    await #expect(throws: AccessError.http(401)) { try await api.usage(tokens, now: now) }
    #expect(!AccessError.http(401).localizedDescription.contains("sensitive"))
}
