import XCTest
@testable import AIQuotaKit

final class SharedAuthContextTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SharedAuthContextStore.clearCodex()
        SharedAuthContextStore.clearClaude()
    }

    override func tearDown() {
        SharedAuthContextStore.clearCodex()
        SharedAuthContextStore.clearClaude()
        super.tearDown()
    }

    func testPersistedCookieRoundTripsBackToHTTPCookie() throws {
        let source = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: "claude.ai",
                .path: "/",
                .name: "sessionKey",
                .value: "abc123",
                .secure: true,
                .expires: Date(timeIntervalSince1970: 1_743_200_000),
            ])
        )

        let persisted = PersistedCookie(source)
        let restored = try XCTUnwrap(persisted.httpCookie)

        XCTAssertEqual(restored.name, "sessionKey")
        XCTAssertEqual(restored.value, "abc123")
        XCTAssertEqual(restored.domain, "claude.ai")
        XCTAssertEqual(restored.path, "/")
        XCTAssertTrue(restored.isSecure)
    }

    func testCodexSharedContextRequiresTokenExpiryMoreThanSixtySecondsAway() {
        let now = Date(timeIntervalSince1970: 1_743_076_800)

        let valid = SharedCodexAuthContext(
            sessionToken: "session-token",
            accessToken: "access-token",
            accessTokenExpiresAt: now.addingTimeInterval(120)
        )
        XCTAssertTrue(valid.hasUsableAccessToken(at: now))

        let stale = SharedCodexAuthContext(
            sessionToken: "session-token",
            accessToken: "access-token",
            accessTokenExpiresAt: now.addingTimeInterval(45)
        )
        XCTAssertFalse(stale.hasUsableAccessToken(at: now))
    }

    func testCodexSharedContextRoundTripsThroughStore() throws {
        let source = SharedCodexAuthContext(
            sessionToken: "session-token",
            accessToken: "access-token",
            accessTokenExpiresAt: Date(timeIntervalSince1970: 1_743_200_000)
        )

        SharedAuthContextStore.saveCodex(source)
        let restored = try XCTUnwrap(SharedAuthContextStore.loadCodex())

        XCTAssertEqual(restored, source)
    }

    func testClaudeSharedContextRoundTripsThroughStore() throws {
        let cookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: "claude.ai",
                .path: "/",
                .name: "sessionKey",
                .value: "cookie-value",
                .secure: true,
            ])
        )

        SharedAuthContextStore.saveClaude(orgId: "org-1", cookies: [cookie])
        let restored = try XCTUnwrap(SharedAuthContextStore.loadClaude())

        XCTAssertEqual(restored.orgId, "org-1")
        XCTAssertEqual(restored.cookies.count, 1)
        XCTAssertEqual(restored.cookies.first?.name, "sessionKey")
        XCTAssertEqual(restored.cookies.first?.value, "cookie-value")
    }
}
