import Testing
import Foundation
@testable import AIQuotaKit

@Suite("ClaudeAuthCoordinator state machine", .serialized)
struct ClaudeAuthCoordinatorTests {

    private static let signedOutKey = "claude.signedOutByUser"

    init() {
        // Ensure each test starts clean — parallel tests can bleed UserDefaults
        UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
        UserDefaults.standard.removeObject(forKey: "app.installedAt.v2")
        UserDefaults.standard.removeObject(forKey: "onboarding.v1.hasCompleted")
        SharedDefaults.clearClaudeUsage()
        SharedAuthContextStore.clearClaude()
    }

    private func makeSUT(
        probe: @escaping ClaudeAuthCoordinator.SessionProbe,
        oauthCredentialsLoader: ClaudeAuthCoordinator.OAuthCredentialsLoader? = nil
    ) -> ClaudeAuthCoordinator {
        ClaudeAuthCoordinator(
            probe: probe,
            oauthCredentialsLoader: oauthCredentialsLoader ?? { _ in throw ClaudeOAuthCredentialsError.notFound }
        )
    }

    // MARK: - Bootstrap

    @Test("bootstrap with valid session → authenticated")
    func bootstrapFound() async throws {
        let sut = makeSUT(probe: { .found(orgId: "org-1", cookies: []) })
        await sut.bootstrap()
        let state = await sut.state
        #expect(state == .authenticated)
    }

    @Test("bootstrap with no session → unauthenticated")
    func bootstrapNotFound() async throws {
        let sut = makeSUT(probe: { .notFound })
        await sut.bootstrap()
        let state = await sut.state
        #expect(state == .unauthenticated)
    }

    @Test("bootstrap restores OAuth credentials without allowing Keychain")
    func bootstrapOAuthFileOnly() async throws {
        let allowedKeychainValues = LockIsolated<[Bool]>([])
        let probeCalls = LockIsolated(0)
        let sut = makeSUT(
            probe: {
                probeCalls.withLock { $0 += 1 }
                return .notFound
            },
            oauthCredentialsLoader: { allowKeychain in
                allowedKeychainValues.withLock { $0.append(allowKeychain) }
                #expect(allowKeychain == false)
                return Self.oauthCredentials(accessToken: "file-token")
            }
        )

        await sut.bootstrap()

        #expect(await sut.state == .authenticated)
        #expect(allowedKeychainValues.value == [false])
        #expect(probeCalls.value == 0)
        await #expect(throws: NetworkError.self) {
            _ = try await sut.requestContext()
        }
    }

    @Test("bootstrap skipped when signedOutByUser persisted")
    func bootstrapSkipsWhenSignedOut() async throws {
        UserDefaults.standard.set(true, forKey: Self.signedOutKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.signedOutKey) }

        let sut = makeSUT(probe: { .found(orgId: "org-1", cookies: []) })
        await sut.bootstrap()
        let state = await sut.state
        #expect(state == .signedOutByUser)
    }

    @Test("bootstrap is idempotent after first call")
    func bootstrapIdempotent() async throws {
        let callCount = LockIsolated(0)
        let sut = makeSUT(probe: {
            callCount.withLock { $0 += 1 }
            return .notFound
        })
        await sut.bootstrap()
        await sut.bootstrap()
        #expect(callCount.value == 1)
        let state = await sut.state
        #expect(state == .unauthenticated)
    }

    @Test("bootstrap without sentinel preserves legacy cached state")
    func bootstrapPreservesLegacyCachedState() async throws {
        SharedDefaults.saveClaudeUsage(.placeholder)
        UserDefaults.standard.set(true, forKey: "onboarding.v1.hasCompleted")
        defer {
            SharedDefaults.clearClaudeUsage()
            UserDefaults.standard.removeObject(forKey: "onboarding.v1.hasCompleted")
            UserDefaults.standard.removeObject(forKey: "app.installedAt.v2")
        }

        let sut = makeSUT(probe: { .notFound })
        await sut.bootstrap()

        #expect(SharedDefaults.loadCachedClaudeUsage() != nil)
        #expect(UserDefaults.standard.object(forKey: "app.installedAt.v2") != nil)
    }

    @Test("bootstrap does not revive widget-only shared auth context")
    func bootstrapIgnoresSharedAuthContext() async throws {
        let cookie = try #require(HTTPCookie(properties: [
            .domain: "claude.ai",
            .path: "/",
            .name: "sessionKey",
            .value: "cookie-value",
            .secure: true,
        ]))
        SharedAuthContextStore.saveClaude(orgId: "org-shared", cookies: [cookie])
        defer { SharedAuthContextStore.clearClaude() }
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }

        let sut = makeSUT(probe: { .notFound })
        await sut.bootstrap()

        #expect(await sut.state == .unauthenticated)
        await #expect(throws: NetworkError.self) {
            _ = try await sut.requestContext()
        }
    }

    // MARK: - signIn

    @Test("signIn from authenticated throws invalidTransition")
    func signInIllegalFromAuthenticated() async throws {
        let sut = makeSUT(probe: { .found(orgId: "x", cookies: []) })
        await sut.bootstrap()  // → authenticated
        await #expect(throws: AuthCoordinatorError.self) {
            try await sut.signIn()
        }
    }

    @Test("signIn allows Keychain OAuth and caches it for refresh")
    func signInAllowsKeychainOAuthAndCachesForRefresh() async throws {
        let keychainCalls = LockIsolated(0)
        let sut = makeSUT(
            probe: { .notFound },
            oauthCredentialsLoader: { allowKeychain in
                guard allowKeychain else { throw ClaudeOAuthCredentialsError.notFound }
                keychainCalls.withLock { $0 += 1 }
                return Self.oauthCredentials(accessToken: "keychain-token")
            }
        )

        await sut.bootstrap()
        #expect(await sut.state == .unauthenticated)

        try await sut.signIn()
        #expect(await sut.state == .authenticated)
        #expect(keychainCalls.value == 1)

        let credentials = try await sut.loadOAuthCredentials(allowKeychain: false)
        #expect(credentials.accessToken == "keychain-token")
        #expect(keychainCalls.value == 1)
    }

    // MARK: - signOut

    @Test("signOut from authenticated transitions to signedOutByUser")
    func signOutFromAuthenticated() async throws {
        UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
        let sut = makeSUT(probe: { .found(orgId: "org-1", cookies: []) })
        await sut.bootstrap()
        #expect(await sut.state == .authenticated)
        try await sut.signOut()
        #expect(await sut.state == .signedOutByUser)
        // Also verify the UserDefaults flag was set
        #expect(UserDefaults.standard.bool(forKey: Self.signedOutKey) == true)
        // Clean up
        UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
    }

    @Test("signOut from unknown throws invalidTransition")
    func signOutFromUnknownThrows() async throws {
        let sut = makeSUT(probe: { .notFound })
        // Do NOT call bootstrap — coordinator is in .unknown
        await #expect(throws: AuthCoordinatorError.self) {
            try await sut.signOut()
        }
    }

    @Test("signOut from unauthenticated is a no-op")
    func signOutNoOpFromUnauthenticated() async throws {
        let sut = makeSUT(probe: { .notFound })
        await sut.bootstrap()
        try await sut.signOut()
        let state = await sut.state
        #expect(state == .unauthenticated)
    }

    @Test("signOut from signedOutByUser is a no-op")
    func signOutNoOpFromSignedOutByUser() async throws {
        UserDefaults.standard.set(true, forKey: Self.signedOutKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.signedOutKey) }
        let sut = makeSUT(probe: { .notFound })
        await sut.bootstrap()
        try await sut.signOut()
        let state = await sut.state
        #expect(state == .signedOutByUser)
    }

    // MARK: - revalidateSessionAfterAuthFailure

    @Test("revalidate from unauthenticated returns false without transition")
    func revalidateFromWrongState() async throws {
        let sut = makeSUT(probe: { .notFound })
        await sut.bootstrap()
        let result = await sut.revalidateSessionAfterAuthFailure()
        #expect(result == false)
        let state = await sut.state
        #expect(state == .unauthenticated)
    }

    @Test("revalidate from authenticated with no session → unauthenticated, returns false")
    func revalidateFailure() async throws {
        let callCount = LockIsolated(0)
        let sut = makeSUT(probe: {
            let count = callCount.withLock { (n: inout Int) -> Int in
                n += 1
                return n
            }
            return count == 1 ? .found(orgId: "x", cookies: []) : .notFound
        })
        await sut.bootstrap()
        let stateAfterBootstrap = await sut.state
        #expect(stateAfterBootstrap == .authenticated)
        let result = await sut.revalidateSessionAfterAuthFailure()
        #expect(result == false)
        let stateAfterRevalidate = await sut.state
        #expect(stateAfterRevalidate == .unauthenticated)
    }

    @Test("revalidate from authenticated with valid session stays authenticated, returns true")
    func revalidateSuccess() async throws {
        let sut = makeSUT(probe: { .found(orgId: "x", cookies: []) })
        await sut.bootstrap()
        let result = await sut.revalidateSessionAfterAuthFailure()
        #expect(result == true)
        #expect(await sut.state == .authenticated)
    }

    // MARK: - requestContext

    @Test("requestContext throws when not authenticated")
    func requestContextUnauthenticated() async throws {
        let sut = makeSUT(probe: { .notFound })
        await sut.bootstrap()
        await #expect(throws: NetworkError.self) {
            _ = try await sut.requestContext()
        }
    }

    @Test("requestContext returns orgId when authenticated")
    func requestContextAuthenticated() async throws {
        let sut = makeSUT(probe: { .found(orgId: "org-42", cookies: []) })
        await sut.bootstrap()
        let ctx = try await sut.requestContext()
        #expect(ctx.orgId == "org-42")
    }

    private static func oauthCredentials(accessToken: String) -> ClaudeOAuthCredentials {
        ClaudeOAuthCredentials(
            accessToken: accessToken,
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(3_600),
            scopes: ["user:profile"],
            rateLimitTier: nil,
            subscriptionType: nil
        )
    }
}
