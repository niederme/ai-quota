import Foundation
import Testing
@testable import AIQuotaKit

@Suite("Codex OAuth credentials store")
struct CodexOAuthCredentialsStoreTests {
    @Test("parses Codex CLI OAuth credentials")
    func parsesCodexCLICredentials() throws {
        let expiresAt = Date().addingTimeInterval(3_600)
        let token = jwt(exp: expiresAt)
        let credentials = try CodexOAuthCredentialsStore.parse(data: Data("""
        {
          "auth_mode": "chatgpt",
          "last_refresh": "2026-05-17T12:00:00Z",
          "tokens": {
            "access_token": "\(token)",
            "refresh_token": "refresh-token",
            "id_token": "id-token",
            "account_id": "account-123"
          }
        }
        """.utf8))

        #expect(credentials.accessToken == token)
        #expect(credentials.refreshToken == "refresh-token")
        #expect(credentials.idToken == "id-token")
        #expect(credentials.accountID == "account-123")
        #expect(credentials.lastRefresh != nil)
        #expect(credentials.expiresAt != nil)
        #expect(!credentials.isExpired)
    }

    @Test("loadUsable rejects expired access tokens")
    func loadUsableRejectsExpiredAccessTokens() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let codexHome = root.appending(path: ".codex")
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)

        try Data("""
        {
          "tokens": {
            "access_token": "\(jwt(exp: Date().addingTimeInterval(-60)))"
          }
        }
        """.utf8).write(to: codexHome.appending(path: "auth.json"))

        #expect(throws: CodexOAuthCredentialsError.expired) {
            _ = try CodexOAuthCredentialsStore.loadUsable(env: ["HOME": root.path])
        }
    }

    @Test("derives Team workspace account ID from ID token claims")
    func derivesTeamWorkspaceAccountIDFromIDToken() throws {
        let accessToken = jwt(exp: Date().addingTimeInterval(3_600))
        let idToken = jwt(payload: [
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "team-account-123",
                "chatgpt_plan_type": "team",
            ],
        ])

        let credentials = try CodexOAuthCredentialsStore.parse(data: Data("""
        {
          "tokens": {
            "access_token": "\(accessToken)",
            "id_token": "\(idToken)"
          }
        }
        """.utf8))

        #expect(credentials.accountID == "team-account-123")
    }

    @Test("CODEX_HOME wins over home auth path")
    func codexHomeWins() throws {
        let root = temporaryDirectory()
        let codexHome = root.appending(path: "custom-codex")
        defer { try? FileManager.default.removeItem(at: root) }

        let url = CodexOAuthCredentialsStore.authURL(env: [
            "HOME": root.path,
            "CODEX_HOME": codexHome.path
        ])

        #expect(url.path == codexHome.appending(path: "auth.json").path)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    private func jwt(exp: Date) -> String {
        jwt(payload: ["exp": Int(exp.timeIntervalSince1970)])
    }

    private func jwt(payload: [String: Any]) -> String {
        let header = try! JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let payload = try! JSONSerialization.data(withJSONObject: payload)
        return "\(base64URL(header)).\(base64URL(payload)).signature"
    }

    private func base64URL(_ string: String) -> String {
        base64URL(Data(string.utf8))
    }

    private func base64URL(_ data: Data) -> String {
        data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
