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

    func testMissingOrganizationOffersAccountReconnectOnce() {
        var gate = ClaudeReconnectPromptGate()
        XCTAssertTrue(gate.shouldPrompt(for: .organizationReconnectRequired, signInVisible: false))
        XCTAssertFalse(gate.shouldPrompt(for: .organizationReconnectRequired, signInVisible: false))
    }

    @MainActor
    func testWebOrganizationProbeDistinguishesAuthFromChallenge() {
        let classify = ClaudeWebDetailsSession.responseError
        XCTAssertEqual(classify(401, "application/json", false, false), .http(401))
        XCTAssertEqual(classify(403, "application/json", false, false), .http(403))
        XCTAssertEqual(classify(403, "text/html", true, true), .challenge)
        XCTAssertEqual(classify(200, "text/html", false, true), .notSignedIn)
        XCTAssertEqual(classify(500, "application/json", false, false), .http(500))
        XCTAssertNil(classify(200, "application/json", false, false))
        XCTAssertEqual(ClaudeWebDetailsSession.organizationProbeFailureState(ClaudeWebDetailError.http(401)), .signInRequired)
        XCTAssertEqual(ClaudeWebDetailsSession.organizationProbeFailureState(ClaudeWebDetailError.http(403)), .signInRequired)
        XCTAssertEqual(ClaudeWebDetailsSession.organizationProbeFailureState(ClaudeWebDetailError.notSignedIn), .signInRequired)
        XCTAssertEqual(ClaudeWebDetailsSession.organizationProbeFailureState(ClaudeWebDetailError.challenge), .unavailable)
        XCTAssertEqual(ClaudeWebDetailsSession.organizationProbeFailureState(ClaudeWebDetailError.http(500)), .unavailable)
        XCTAssertTrue(ClaudeWebDetailsSession.detailRequiresSignIn(ClaudeWebDetailError.http(401)))
        XCTAssertTrue(ClaudeWebDetailsSession.detailRequiresSignIn(ClaudeWebDetailError.notSignedIn))
        XCTAssertFalse(ClaudeWebDetailsSession.detailRequiresSignIn(ClaudeWebDetailError.http(403)))
    }
}

final class ClaudeWebSessionRollbackTests: XCTestCase {
    @MainActor
    func testNavigationWithoutCompletionBecomesRetryable() async {
        let session = ClaudeWebDetailsSession()
        session.checkingTimeout = .milliseconds(40)
        session.start(organization: .verified(UUID().uuidString), loadPage: false)
        XCTAssertEqual(session.state, .checking)
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(session.state, .unavailable)
    }

    @MainActor
    func testVerifiedWebSessionCommitsBeforeAutomaticSheetDismissal() async throws {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let name = "next-auth.session-token.aiquota-success-\(UUID().uuidString)"
        func cookie(_ value: String) throws -> HTTPCookie {
            try XCTUnwrap(HTTPCookie(properties: [
                .domain: "claude.ai", .path: "/", .name: name,
                .value: value, .secure: "TRUE"
            ]))
        }
        let previous = try cookie("previous")
        await withCheckedContinuation { continuation in
            store.setCookie(previous) { continuation.resume() }
        }
        let session = ClaudeWebDetailsSession()
        let organizationID = UUID().uuidString
        session.start(organization: .verified(organizationID), loadPage: false)
        await session.beginReconnect(loadPage: false)
        let signedIn = try cookie("new-sign-in")
        await withCheckedContinuation { continuation in
            store.setCookie(signedIn) { continuation.resume() }
        }

        session.acceptVerifiedOrganization(organizationID)
        // SwiftUI's automatic sheet dismissal used to call rollback here.
        await session.cancelReconnect()
        session.start(organization: .verified(organizationID), loadPage: false)
        let after = await cookies(in: store)
        XCTAssertEqual(session.state, .ready)
        XCTAssertTrue(after.contains(where: { $0.name == name && $0.value == "new-sign-in" }))
        await withCheckedContinuation { continuation in
            store.delete(signedIn) { continuation.resume() }
        }
    }

    @MainActor
    func testClosingReconnectRestoresPreviousClaudeCookie() async throws {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let name = "next-auth.session-token.aiquota-test-\(UUID().uuidString)"
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

        let attemptedName = "next-auth.session-token.aiquota-abandoned-\(UUID().uuidString)"
        let attemptedCookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "claude.ai", .path: "/", .name: attemptedName,
            .value: "abandoned-session", .secure: "TRUE"
        ]))
        await withCheckedContinuation { continuation in
            store.setCookie(attemptedCookie) { continuation.resume() }
        }

        await session.cancelReconnect()
        let after = await cookies(in: store)
        XCTAssertTrue(after.contains(where: { $0.name == name && $0.value == "previous-session" }))
        XCTAssertFalse(after.contains(where: { $0.name == attemptedName }))
        await withCheckedContinuation { continuation in
            store.delete(cookie) { continuation.resume() }
        }
    }

    @MainActor
    func testReconnectPreservesCloudflareMitigationCookie() async throws {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "claude.ai", .path: "/", .name: "cf_clearance",
            .value: "test-\(UUID().uuidString)", .secure: "TRUE"
        ]))
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) { continuation.resume() }
        }
        let session = ClaudeWebDetailsSession()
        await session.beginReconnect(loadPage: false)
        let during = await cookies(in: store)
        XCTAssertTrue(during.contains(where: { $0.name == "cf_clearance" && $0.value == cookie.value }))
        await session.cancelReconnect()
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
