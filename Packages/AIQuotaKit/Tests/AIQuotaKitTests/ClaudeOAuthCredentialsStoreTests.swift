import Foundation
import Testing
@testable import AIQuotaKit

@Suite("Claude OAuth credentials store")
struct ClaudeOAuthCredentialsStoreTests {
    @Test("parses Claude Code OAuth credentials")
    func parsesClaudeCodeCredentials() throws {
        let expiresAt = Date().addingTimeInterval(3_600)
        let credentials = try ClaudeOAuthCredentialsStore.parse(data: Data("""
        {
          "claudeAiOauth": {
            "accessToken": "access-token",
            "refreshToken": "refresh-token",
            "expiresAt": \(Int(expiresAt.timeIntervalSince1970 * 1000)),
            "scopes": ["user:profile", "org:usage"],
            "rateLimitTier": "max",
            "subscriptionType": "pro"
          }
        }
        """.utf8))

        #expect(credentials.accessToken == "access-token")
        #expect(credentials.refreshToken == "refresh-token")
        #expect(credentials.hasRequiredScope)
        #expect(!credentials.isExpired)
        #expect(credentials.rateLimitTier == "max")
        #expect(credentials.subscriptionType == "pro")
    }

    @Test("loadUsable rejects expired credentials and credentials without user profile scope")
    func loadUsableValidatesExpiryAndScope() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: ".claude"), withIntermediateDirectories: true)

        let credentialsURL = root.appending(path: ".claude/.credentials.json")
        try Data("""
        {
          "claudeAiOauth": {
            "accessToken": "access-token",
            "expiresAt": \(Int(Date().addingTimeInterval(-60).timeIntervalSince1970 * 1000)),
            "scopes": ["user:profile"]
          }
        }
        """.utf8).write(to: credentialsURL)

        #expect(throws: ClaudeOAuthCredentialsError.expired) {
            _ = try ClaudeOAuthCredentialsStore.loadUsable(env: ["HOME": root.path])
        }

        try Data("""
        {
          "claudeAiOauth": {
            "accessToken": "access-token",
            "expiresAt": \(Int(Date().addingTimeInterval(3_600).timeIntervalSince1970 * 1000)),
            "scopes": ["org:usage"]
          }
        }
        """.utf8).write(to: credentialsURL)

        #expect(throws: ClaudeOAuthCredentialsError.missingScope) {
            _ = try ClaudeOAuthCredentialsStore.loadUsable(env: ["HOME": root.path])
        }
    }

    @Test("CLAUDE_CONFIG_DIR wins over home credentials path")
    func claudeConfigDirWins() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let configDir = root.appending(path: "config")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let url = ClaudeOAuthCredentialsStore.credentialsURL(env: [
            "HOME": root.path,
            "CLAUDE_CONFIG_DIR": "\(configDir.path),ignored"
        ])

        #expect(url.path == configDir.appending(path: ".credentials.json").path)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }
}
