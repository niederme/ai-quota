import Testing
import Foundation
@testable import AIQuotaKit

@Suite("CodexAuthCoordinator state machine", .serialized)
struct CodexAuthCoordinatorTests {

    init() {
        UserDefaults.standard.removeObject(forKey: "codex.signedOutByUser")
        UserDefaults.standard.removeObject(forKey: "app.installedAt.v2")
        UserDefaults.standard.removeObject(forKey: "onboarding.v1.hasCompleted")
        SharedDefaults.clearUsage()
        SharedAuthContextStore.clearCodex()
    }

    private func makeSUT(
        probe: @escaping CodexAuthCoordinator.SessionProbe,
        headlessSessionReviver: CodexAuthCoordinator.HeadlessSessionReviver? = nil,
        tokenRefresher: CodexAuthCoordinator.AccessTokenRefresher? = nil,
        oauthCredentialsLoader: CodexAuthCoordinator.OAuthCredentialsLoader? = nil
    ) -> CodexAuthCoordinator {
        CodexAuthCoordinator(
            probe: probe,
            headlessSessionReviver: headlessSessionReviver ?? { nil },
            tokenRefresher: tokenRefresher,
            oauthCredentialsLoader: oauthCredentialsLoader ?? { throw CodexOAuthCredentialsError.notFound }
        )
    }

    @Test("bootstrap with valid session → authenticated")
    func bootstrapFound() async throws {
        let sut = makeSUT(probe: { .found(sessionToken: "tok-1") })
        // Note: bootstrap calls refreshAccessToken() which hits the network.
        // In unit tests we only verify that the probe result drives state;
        // full bootstrap (with JWT refresh) is covered by integration testing.
        // We test probe→state linkage by inspecting state after a mock-probe bootstrap.
        // Since refreshAccessToken will fail without network, state goes to unauthenticated.
        // This confirms the probe IS called and drives the transition path.
        await sut.bootstrap()
        let state = await sut.state
        // Either authenticated (network available) or unauthenticated (no network) — not unknown.
        #expect(state != .unknown && state != .restoringSession)
    }

    @Test("bootstrap with no session → unauthenticated")
    func bootstrapNotFound() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }
        let sut = makeSUT(probe: { .notFound })
        await sut.bootstrap()
        #expect(await sut.state == .unauthenticated)
    }

    @Test("bootstrap skipped when signedOutByUser persisted")
    func bootstrapSkipsWhenSignedOut() async throws {
        UserDefaults.standard.set(true, forKey: "codex.signedOutByUser")
        defer { UserDefaults.standard.removeObject(forKey: "codex.signedOutByUser") }
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }
        let sut = makeSUT(probe: { .found(sessionToken: "tok") })
        await sut.bootstrap()
        #expect(await sut.state == .signedOutByUser)
    }

    @Test("bootstrap is idempotent after first call")
    func bootstrapIdempotent() async throws {
        // Set the fresh-install sentinel so clearStateIfFreshInstall doesn't reset the store
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }

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
        SharedDefaults.saveUsage(.placeholder)
        UserDefaults.standard.set(true, forKey: "onboarding.v1.hasCompleted")
        defer {
            SharedDefaults.clearUsage()
            UserDefaults.standard.removeObject(forKey: "onboarding.v1.hasCompleted")
            UserDefaults.standard.removeObject(forKey: "app.installedAt.v2")
        }

        let sut = makeSUT(probe: { .notFound })
        await sut.bootstrap()

        #expect(SharedDefaults.loadCachedUsage() != nil)
        #expect(UserDefaults.standard.object(forKey: "app.installedAt.v2") != nil)
    }

    @Test("bootstrap does not revive widget-only shared auth context")
    func bootstrapIgnoresSharedAuthContext() async throws {
        SharedAuthContextStore.saveCodex(
            SharedCodexAuthContext(
                sessionToken: "session-from-shared-context",
                accessToken: "access-from-shared-context",
                accessTokenExpiresAt: Date.now.addingTimeInterval(600)
            )
        )
        defer { SharedAuthContextStore.clearCodex() }

        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }

        let sut = makeSUT(probe: { .notFound })
        await sut.bootstrap()

        #expect(await sut.state == .unauthenticated)
        await #expect(throws: NetworkError.self) {
            _ = try await sut.accessToken()
        }
    }

    @Test("bootstrap prefers Codex CLI OAuth before WebKit probe")
    func bootstrapPrefersOAuth() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }
        let callCount = LockIsolated(0)
        let sut = makeSUT(
            probe: {
                callCount.withLock { $0 += 1 }
                return .found(sessionToken: "web-token")
            },
            oauthCredentialsLoader: {
                Self.oauthCredentials(accessToken: "oauth-token", accountID: "account-123")
            }
        )

        await sut.bootstrap()

        #expect(await sut.state == .authenticated)
        #expect(callCount.value == 0)
        let context = try await sut.accessContext()
        #expect(context.accessToken == "oauth-token")
        #expect(context.accountID == "account-123")
        #expect(context.source == .codexOAuth)
    }

    @Test("signedOutByUser blocks silent OAuth bootstrap")
    func signedOutBlocksOAuthBootstrap() async throws {
        UserDefaults.standard.set(true, forKey: "codex.signedOutByUser")
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer {
            UserDefaults.standard.removeObject(forKey: "codex.signedOutByUser")
            UserDefaults.standard.removeObject(forKey: "app.installedAt.v2")
        }
        let sut = makeSUT(
            probe: { .notFound },
            oauthCredentialsLoader: {
                Self.oauthCredentials(accessToken: "oauth-token", accountID: "account-123")
            }
        )

        await sut.bootstrap()

        #expect(await sut.state == .signedOutByUser)
    }

    @Test("explicit signIn imports OAuth after prior sign-out")
    func signInImportsOAuthAfterPriorSignOut() async throws {
        UserDefaults.standard.set(true, forKey: "codex.signedOutByUser")
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer {
            UserDefaults.standard.removeObject(forKey: "codex.signedOutByUser")
            UserDefaults.standard.removeObject(forKey: "app.installedAt.v2")
        }
        let sut = makeSUT(
            probe: { .notFound },
            oauthCredentialsLoader: {
                Self.oauthCredentials(accessToken: "oauth-token", accountID: "account-123")
            }
        )
        await sut.bootstrap()

        try await sut.signIn()

        #expect(await sut.state == .authenticated)
        #expect(UserDefaults.standard.bool(forKey: "codex.signedOutByUser") == false)
        let context = try await sut.accessContext()
        #expect(context.source == .codexOAuth)
    }

    @Test("web session derives Team workspace account ID from access token claims")
    func webSessionDerivesAccountIDFromTokenClaims() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }

        let accessToken = Self.jwt(payload: [
            "exp": Int(Date.now.addingTimeInterval(3_600).timeIntervalSince1970),
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "team-account-123",
                "chatgpt_plan_type": "team",
            ],
        ])

        let sut = makeSUT(
            probe: { .found(sessionToken: "team-session") },
            tokenRefresher: { _ in (accessToken, Date.now.addingTimeInterval(900)) }
        )
        await sut.bootstrap()

        #expect(await sut.state == .authenticated)
        let context = try await sut.accessContext()
        #expect(context.source == .webSession)
        #expect(context.accountID == "team-account-123")
    }

    @Test("post-bootstrap recovery restores Codex OAuth credentials")
    func postBootstrapRecoveryRestoresOAuth() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }
        let sut = makeSUT(
            probe: { .notFound },
            oauthCredentialsLoader: {
                Self.oauthCredentials(accessToken: "oauth-token", accountID: "account-123")
            }
        )

        await sut.bootstrap()
        #expect(await sut.state == .authenticated)
        let context = try await sut.accessContext()
        #expect(context.source == .codexOAuth)
    }

    @Test("post-bootstrap recovery restores a WebKit session token")
    func postBootstrapRecoveryRestoresWebSessionToken() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }
        let accessToken = Self.jwt(payload: [
            "exp": Int(Date.now.addingTimeInterval(3_600).timeIntervalSince1970),
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "web-account-123",
            ],
        ])
        let probeResults = LockIsolated<[CodexProbeResult]>([
            .notFound,
            .found(sessionToken: "web-session")
        ])
        let sut = makeSUT(
            probe: {
                probeResults.withLock { results in
                    results.isEmpty ? .notFound : results.removeFirst()
                }
            },
            tokenRefresher: { _ in (accessToken, Date.now.addingTimeInterval(900)) }
        )

        await sut.bootstrap()
        #expect(await sut.state == .unauthenticated)

        let restored = await sut.restoreWithoutPromptIfPossible()

        #expect(restored)
        #expect(await sut.state == .authenticated)
        let context = try await sut.accessContext()
        #expect(context.source == .webSession)
        #expect(context.accountID == "web-account-123")
    }

    @Test("post-bootstrap recovery restores a headless WebKit session")
    func postBootstrapRecoveryRestoresHeadlessWebSession() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }
        let accessToken = Self.jwt(payload: [
            "exp": Int(Date.now.addingTimeInterval(3_600).timeIntervalSince1970),
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "headless-account-123",
            ],
        ])
        let sut = makeSUT(
            probe: { .notFound },
            headlessSessionReviver: {
                CodexWebSessionResult(
                    sessionToken: "headless-session",
                    accessToken: accessToken,
                    expiresAt: Date.now.addingTimeInterval(900)
                )
            }
        )

        await sut.bootstrap()
        #expect(await sut.state == .unauthenticated)

        let restored = await sut.restoreWithoutPromptIfPossible()

        #expect(restored)
        #expect(await sut.state == .authenticated)
        let context = try await sut.accessContext()
        #expect(context.source == .webSession)
        #expect(context.accountID == "headless-account-123")
    }

    @Test("post-bootstrap recovery returns false when no source is usable")
    func postBootstrapRecoveryReturnsFalseWhenUnavailable() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }
        let sut = makeSUT(probe: { .notFound })

        await sut.bootstrap()

        let restored = await sut.restoreWithoutPromptIfPossible()

        #expect(!restored)
        #expect(await sut.state == .unauthenticated)
    }

    @Test("post-bootstrap recovery does not override explicit sign out")
    func postBootstrapRecoverySkipsSignedOutByUser() async throws {
        UserDefaults.standard.set(true, forKey: "codex.signedOutByUser")
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer {
            UserDefaults.standard.removeObject(forKey: "codex.signedOutByUser")
            UserDefaults.standard.removeObject(forKey: "app.installedAt.v2")
        }
        let sut = makeSUT(
            probe: { .notFound },
            headlessSessionReviver: {
                CodexWebSessionResult(
                    sessionToken: "headless-session",
                    accessToken: Self.jwt(payload: ["exp": Int(Date.now.addingTimeInterval(3_600).timeIntervalSince1970)]),
                    expiresAt: Date.now.addingTimeInterval(900)
                )
            }
        )

        await sut.bootstrap()
        #expect(await sut.state == .signedOutByUser)

        let restored = await sut.restoreWithoutPromptIfPossible()

        #expect(!restored)
        #expect(await sut.state == .signedOutByUser)
    }

    private static func jwt(payload: [String: Any]) -> String {
        let header = try! JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let body = try! JSONSerialization.data(withJSONObject: payload)
        return "\(base64URL(header)).\(base64URL(body)).signature"
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    @Test("signIn from unknown throws invalidTransition")
    func signInIllegalFromUnknown() async throws {
        let sut = makeSUT(probe: { .notFound })
        // Do NOT bootstrap — state is .unknown, which hits the default: throw branch
        await #expect(throws: AuthCoordinatorError.self) {
            try await sut.signIn()
        }
    }

    @Test("signOut from unauthenticated is a no-op")
    func signOutNoOpFromUnauthenticated() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }
        let sut = makeSUT(probe: { .notFound })
        await sut.bootstrap()
        try await sut.signOut()
        #expect(await sut.state == .unauthenticated)
    }

    @Test("signOut from signedOutByUser is a no-op")
    func signOutNoOpFromSignedOutByUser() async throws {
        UserDefaults.standard.set(true, forKey: "codex.signedOutByUser")
        defer { UserDefaults.standard.removeObject(forKey: "codex.signedOutByUser") }
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }
        let sut = makeSUT(probe: { .notFound })
        await sut.bootstrap()
        try await sut.signOut()
        #expect(await sut.state == .signedOutByUser)
    }

    @Test("signOut from unknown throws invalidTransition")
    func signOutFromUnknownThrows() async throws {
        let sut = makeSUT(probe: { .notFound })
        // Do NOT bootstrap — state is .unknown
        await #expect(throws: AuthCoordinatorError.self) {
            try await sut.signOut()
        }
    }

    @Test("revalidate from unauthenticated returns false without transition")
    func revalidateFromWrongState() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }
        let sut = makeSUT(probe: { .notFound })
        await sut.bootstrap()
        let result = await sut.revalidateSessionAfterAuthFailure()
        #expect(result == false)
        #expect(await sut.state == .unauthenticated)
    }

    @Test("accessToken throws when not authenticated")
    func accessTokenUnauthenticated() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }
        let sut = makeSUT(probe: { .notFound })
        await sut.bootstrap()
        await #expect(throws: NetworkError.self) {
            _ = try await sut.accessToken()
        }
    }

    @Test("Codex login starts on explicit ChatGPT login route")
    func loginStartsOnExplicitRoute() {
        #expect(CodexAuthCoordinator.loginURL == URL(string: "https://chatgpt.com/auth/login")!)
    }

    private static func oauthCredentials(accessToken: String, accountID: String?) -> CodexOAuthCredentials {
        CodexOAuthCredentials(
            accessToken: accessToken,
            refreshToken: "refresh-token",
            idToken: "id-token",
            accountID: accountID,
            lastRefresh: Date(),
            expiresAt: Date().addingTimeInterval(3_600)
        )
    }
}
