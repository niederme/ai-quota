import XCTest
import WebKit
@testable import AIQuota_iOS

final class ClaudeReconnectPromptTests: XCTestCase {
    func testPromptsOnceForExpiredOrMismatchedWebSession() {
        var gate = ClaudeReconnectPromptGate()
        XCTAssertFalse(gate.shouldPrompt(for: .checking, signInVisible: false))
        XCTAssertTrue(gate.shouldPrompt(for: .signInRequired, signInVisible: false))
        // Cancel and subsequent navigation in this visit retain the connection
        // and must not loop back into the same alert.
        XCTAssertFalse(gate.shouldPrompt(for: .signInRequired, signInVisible: false))
        XCTAssertFalse(gate.shouldPrompt(for: .accountMismatch, signInVisible: false))
    }

    func testTransientFailuresDoNotDemandReauthentication() {
        var gate = ClaudeReconnectPromptGate()
        XCTAssertFalse(gate.shouldPrompt(for: .unavailable, signInVisible: false))
        XCTAssertFalse(gate.hasPrompted)
        XCTAssertFalse(gate.shouldPrompt(for: .accountMismatch, signInVisible: true))
        XCTAssertFalse(gate.hasPrompted)
        XCTAssertTrue(gate.shouldPrompt(for: .accountMismatch, signInVisible: false))
    }
}

final class ClaudeWebSessionRollbackTests: XCTestCase {
    @MainActor
    func testClosingReconnectRestoresPreviousClaudeCookie() async throws {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let name = "aiquota-reconnect-test-\(UUID().uuidString)"
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "claude.ai", .path: "/", .name: name,
            .value: "previous-session", .secure: "TRUE"
        ]))
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) { continuation.resume() }
        }
        let session = ClaudeWebDetailsSession()
        await session.beginReconnect(loadPage: false)
        let during = await cookies(in: store)
        XCTAssertFalse(during.contains(where: { $0.name == name }))

        await session.cancelReconnect()
        let after = await cookies(in: store)
        XCTAssertTrue(after.contains(where: { $0.name == name && $0.value == "previous-session" }))
        await withCheckedContinuation { continuation in
            store.delete(cookie) { continuation.resume() }
        }
    }

    @MainActor
    private func cookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
    }
}
