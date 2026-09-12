import XCTest
import MobileAccessCore
@testable import AIQuota_iOS

final class TokenStoreTests: XCTestCase {
    func testSecureRoundTripAndDeletion() throws {
        // Dedicated test account cannot overwrite a connected user's token.
        let account = "test-\(UUID().uuidString)"
        defer { try? TokenStore.clear(account: account) }
        XCTAssertNil(try TokenStore.load(account: account))
        let tokens = try JSONDecoder().decode(CodexTokens.self, from: Data(
            #"{"accessToken":"test-access","refreshToken":"test-refresh","accountID":"test","expiresAt":900000000}"#.utf8))
        try TokenStore.save(tokens, account: account)
        XCTAssertEqual(try TokenStore.load(account: account)?.accessToken, "test-access")
        // Exercise update as well as initial insert.
        try TokenStore.save(tokens, account: account)
        XCTAssertEqual(try TokenStore.load(account: account)?.refreshToken, "test-refresh")
        try TokenStore.clear(account: account)
        XCTAssertNil(try TokenStore.load(account: account))
    }
}

extension TokenStoreTests {
    func testClaudeStorageDoesNotTouchCodex() throws {
        let account = "test-\(UUID().uuidString)"
        defer {
            try? TokenStore.clear(account: account)
            try? ClaudeTokenStore.clear(account: account)
        }
        let codex = try JSONDecoder().decode(CodexTokens.self, from: Data(
            #"{"accessToken":"codex-test","expiresAt":900000000}"#.utf8))
        let claude = try JSONDecoder().decode(ClaudeTokens.self, from: Data(
            #"{"accessToken":"claude-test","refreshToken":"claude-refresh","expiresAt":900000000}"#.utf8))
        try TokenStore.save(codex, account: account)
        try ClaudeTokenStore.save(claude, account: account)
        try ClaudeTokenStore.save(claude, account: account)
        XCTAssertEqual(try ClaudeTokenStore.load(account: account)?.refreshToken, "claude-refresh")
        XCTAssertEqual(try TokenStore.load(account: account)?.accessToken, "codex-test")
        try ClaudeTokenStore.clear(account: account)
        XCTAssertNil(try ClaudeTokenStore.load(account: account))
        XCTAssertEqual(try TokenStore.load(account: account)?.accessToken, "codex-test")
    }
}


extension TokenStoreTests {
    func testWidgetPayloadExcludesRefreshCredential() throws {
        let tokens = try JSONDecoder().decode(CodexTokens.self, from: Data(
            #"{"accessToken":"synthetic-access","refreshToken":"private-refresh","accountID":"test","expiresAt":900000000}"#.utf8))
        let data = try WidgetStore.accessOnlyData(tokens)
        let shared = try JSONDecoder().decode(CodexTokens.self, from: data)
        XCTAssertNil(shared.refreshToken)
        XCTAssertEqual(shared.accessToken, tokens.accessToken)
        XCTAssertEqual(shared.expiresAt, tokens.expiresAt)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private-refresh"))
    }
}


extension TokenStoreTests {
    func testSharedAccessKeychainRoundTrip() throws {
        let account = "widget-test-\(UUID().uuidString)"
        defer { try? WidgetStore.clearAccess(account: account) }
        let tokens = try JSONDecoder().decode(CodexTokens.self, from: Data(
            #"{"accessToken":"synthetic-access","refreshToken":"private-refresh","expiresAt":900000000}"#.utf8))
        try WidgetStore.publish(tokens, account: account)
        XCTAssertEqual(try WidgetStore.tokens(account: account)?.accessToken, tokens.accessToken)
        XCTAssertNil(try WidgetStore.tokens(account: account)?.refreshToken)
        try WidgetStore.publish(tokens, account: account)
        try WidgetStore.clearAccess(account: account)
        XCTAssertNil(try WidgetStore.tokens(account: account))
    }
}
