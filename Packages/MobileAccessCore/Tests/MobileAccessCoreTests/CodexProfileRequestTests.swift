import Foundation
import Testing
@testable import MobileAccessCore

private struct ProfileTransport: HTTPTransport {
    let status: Int
    func send(_ request: URLRequest) async throws -> HTTPResult {
        #expect(request.url?.path == "/backend-api/profiles/me/page")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "test-account")
        return HTTPResult(data: Data(#"{"page":{"activity_graph":{"daily_usage_buckets":[{"start_date":"2026-01-01","tokens":12}]}}}"#.utf8), status: status)
    }
}
private func profileCredential(_ access: String = "synthetic", account: String = "test-account") throws -> CodexTokens {
    let data = try JSONSerialization.data(withJSONObject: ["accessToken": access, "accountID": account, "expiresAt": 900000000])
    return try JSONDecoder().decode(CodexTokens.self, from: data)
}
@Test func profileRequestUsesExistingCredentialAndReturnsTokens() async throws {
    let credential = try profileCredential()
    let history = try await CodexAPI(transport: ProfileTransport(status: 200)).tokenHistory(credential)
    #expect(history?.tokensByDate["2026-01-01"] == 12)
    #expect(history?.scopeID == CodexAPI.tokenHistoryScope(credential))
}
@Test func unavailableProfileRemainsOptional() async throws {
    for status in [403, 404] {
        #expect(try await CodexAPI(transport: ProfileTransport(status: status)).tokenHistory(profileCredential()) == nil)
    }
}
@Test func profileScopeSeparatesAccountsButSurvivesCredentialRenewal() throws {
    let scope = CodexAPI.tokenHistoryScope(try profileCredential())
    #expect(scope == CodexAPI.tokenHistoryScope(try profileCredential("rotated")))
    #expect(scope != CodexAPI.tokenHistoryScope(try profileCredential(account: "other")))
    #expect(CodexAPI.tokenHistoryScope(try profileCredential("rotated", account: "")) !=
            CodexAPI.tokenHistoryScope(try profileCredential(account: "")))
}
