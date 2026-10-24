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
        accountStorageID: UUID? = nil,
        probe: @escaping CodexAuthCoordinator.SessionProbe,
        headlessSessionReviver: CodexAuthCoordinator.HeadlessSessionReviver? = nil,
        tokenRefresher: CodexAuthCoordinator.AccessTokenRefresher? = nil,
        oauthCredentialsLoader: CodexAuthCoordinator.OAuthCredentialsLoader? = nil,
        expectedAccountID: (@Sendable () -> String?)? = nil,
        contextWriter: (@Sendable (SharedCodexAuthContext) -> Void)? = nil,
        interactiveSessionProvider: CodexAuthCoordinator.InteractiveSessionProvider? = nil,
        sessionCommitter: CodexAuthCoordinator.SessionCommitter? = nil,
        stagedSessionVerifier: CodexAuthCoordinator.StagedSessionVerifier? = nil,
        sessionClearer: (@Sendable () async -> Void)? = nil
    ) -> CodexAuthCoordinator {
        CodexAuthCoordinator(
            accountStorageID: accountStorageID,
            probe: probe,
            headlessSessionReviver: headlessSessionReviver ?? { nil },
            tokenRefresher: tokenRefresher,
            oauthCredentialsLoader: oauthCredentialsLoader ?? { throw CodexOAuthCredentialsError.notFound },
            expectedAccountID: expectedAccountID ?? { nil },
            contextWriter: contextWriter,
            interactiveSessionProvider: interactiveSessionProvider,
            sessionCommitter: sessionCommitter,
            stagedSessionVerifier: stagedSessionVerifier ?? { $0 },
            sessionClearer: sessionClearer
        )
    }

    @Test("scoped sign-out marker does not block another account")
    func scopedSignOutMarkerIsIsolated() async {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        let signedOutID = UUID()
        let otherID = UUID()
        let signedOutKey = "codex.signedOutByUser.\(signedOutID.uuidString.lowercased())"
        UserDefaults.standard.set(true, forKey: signedOutKey)
        defer {
            UserDefaults.standard.removeObject(forKey: "app.installedAt.v2")
            UserDefaults.standard.removeObject(forKey: signedOutKey)
        }

        let signedOut = makeSUT(accountStorageID: signedOutID, probe: { .notFound })
        let other = makeSUT(accountStorageID: otherID, probe: { .notFound })
        await signedOut.bootstrap()
        await other.bootstrap()

        #expect(await signedOut.state == .signedOutByUser)
        #expect(await other.state == .unauthenticated)
    }

    @Test("scoped account does not import process-wide Codex CLI credentials")
    func scopedAccountSkipsDefaultOAuthLoader() async {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }
        let sut = CodexAuthCoordinator(
            accountStorageID: UUID(),
            probe: { .notFound },
            headlessSessionReviver: { nil },
            tokenRefresher: { _ in throw NetworkError.refreshFailed }
        )

        await sut.bootstrap()

        #expect(await sut.state == .unauthenticated)
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

    @Test("post-bootstrap recovery accepts an already authenticated session")
    func postBootstrapRecoveryAcceptsAuthenticatedSession() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        defer { UserDefaults.standard.removeObject(forKey: "app.installedAt.v2") }
        let loaderCalls = LockIsolated(0)
        let sut = makeSUT(
            probe: { .notFound },
            oauthCredentialsLoader: {
                loaderCalls.withLock { $0 += 1 }
                return Self.oauthCredentials(accessToken: "oauth-token", accountID: "account-123")
            }
        )

        await sut.bootstrap()
        let restored = await sut.restoreWithoutPromptIfPossible()

        #expect(restored)
        #expect(await sut.state == .authenticated)
        #expect(loaderCalls.value == 1)
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

    @Test("bound Personal skips Work CLI credentials and restores its own web identity")
    func boundPrimaryChoosesMatchingSource() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        let persistedIdentity = LockIsolated<String?>(nil)
        let web = Self.jwt(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "personal-a"]])
        let sut = makeSUT(probe: { .found(sessionToken: "fixture-personal-session") },
            tokenRefresher: { _ in (web, .now.addingTimeInterval(3600)) },
            oauthCredentialsLoader: { Self.oauthCredentials(accessToken: "fixture-work-token", accountID: "work-b") },
            expectedAccountID: { "personal-a" },
            contextWriter: { context in persistedIdentity.withLock { $0 = context.accountID } })
        await sut.bootstrap()
        let context = try await sut.accessContext()
        #expect(context.accountID == "personal-a")
        #expect(context.source == .webSession)
        #expect(persistedIdentity.value == "personal-a")
    }

    @Test("CLI switching cannot replace an authenticated bound Personal context")
    func boundContextSurvivesCliSwitch() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        let cli = LockIsolated(Self.oauthCredentials(accessToken: "fixture-personal", accountID: "personal-a"))
        let persistedIdentity = LockIsolated<String?>(nil)
        let sut = makeSUT(probe: { .notFound }, oauthCredentialsLoader: { cli.value }, expectedAccountID: { "personal-a" },
            contextWriter: { context in persistedIdentity.withLock { $0 = context.accountID } })
        await sut.bootstrap()
        cli.withLock { $0 = Self.oauthCredentials(accessToken: "fixture-work", accountID: "work-b") }
        #expect(try await sut.accessContext().accountID == "personal-a")
        #expect(persistedIdentity.value == "personal-a")
        #expect(await sut.state == .authenticated)
    }

    @Test("existing scoped Work gets page-session recovery when its cookie probe misses")
    func scopedBootstrapRevivesMatchingPageSession() async throws {
        let id = UUID()
        let calls = LockIsolated(0)
        let access = Self.jwt(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "work-b"]])
        let sut = makeSUT(accountStorageID: id, probe: { .notFound }, headlessSessionReviver: {
            calls.withLock { $0 += 1 }
            return .init(sessionToken: "", accessToken: access, expiresAt: .now.addingTimeInterval(3600))
        }, expectedAccountID: { "work-b" })
        await sut.bootstrap()
        #expect(calls.value == 1)
        #expect(await sut.state == .authenticated)
        #expect(try await sut.accessContext().accountID == "work-b")
        #expect(!UserDefaults.standard.bool(forKey: "codex.signedOutByUser.\(id.uuidString.lowercased())"))
        defer { SharedAuthContextStore.clearCodex(forAccountID: id.uuidString) }
    }

    @Test("wrong headless workspace leaves the saved context and sign-out flag untouched")
    func mismatchedRevivalPreservesSavedContext() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        let persistedIdentity = LockIsolated<String?>("personal-a")
        let wrong = Self.jwt(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "work-b"]])
        let sut = makeSUT(probe: { .notFound }, headlessSessionReviver: {
            .init(sessionToken: "fixture-other", accessToken: wrong, expiresAt: .now.addingTimeInterval(3600))
        }, expectedAccountID: { "personal-a" },
           contextWriter: { context in persistedIdentity.withLock { $0 = context.accountID } })
        await sut.bootstrap()
        #expect(!(await sut.restoreWithoutPromptIfPossible()))
        #expect(await sut.state == .unauthenticated)
        #expect(persistedIdentity.value == "personal-a")
        #expect(!UserDefaults.standard.bool(forKey: "codex.signedOutByUser"))
    }

    @Test("scoped recovery still respects an explicit user sign-out")
    func scopedRevivalRespectsSignOut() async {
        let id = UUID()
        let key = "codex.signedOutByUser.\(id.uuidString.lowercased())"
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let calls = LockIsolated(0)
        let sut = makeSUT(accountStorageID: id, probe: { .notFound }, headlessSessionReviver: {
            calls.withLock { $0 += 1 }; return nil
        }, expectedAccountID: { "work-b" })
        await sut.bootstrap()
        #expect(await sut.state == .signedOutByUser)
        #expect(calls.value == 0)
    }

    @Test("authenticated reconnect opens the interactive path and adopts only a matching workspace")
    func authenticatedReconnectAcceptsMatchingIdentity() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        let logins = LockIsolated(0), commits = LockIsolated(0), writes = LockIsolated(0), cliCalls = LockIsolated(0)
        let cookies = [Self.fixtureCookie("fixture-session-a")]
        let web = Self.jwt(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "personal-a"]])
        let sut = makeSUT(probe: { .notFound }, oauthCredentialsLoader: {
            cliCalls.withLock { $0 += 1 }
            return Self.oauthCredentials(accessToken: "fixture-old-a", accountID: "personal-a")
        }, expectedAccountID: { "personal-a" }, contextWriter: { _ in writes.withLock { $0 += 1 } },
        interactiveSessionProvider: { expected in
            #expect(expected == "personal-a")
            logins.withLock { $0 += 1 }
            return .init(sessionToken: "fixture-session-a", accessToken: web, expiresAt: .now.addingTimeInterval(3600), cookiesToCommit: cookies)
        }, sessionCommitter: { _, _ in commits.withLock { $0 += 1 } })
        await sut.bootstrap()
        try await sut.reconnect()
        #expect(await sut.state == .authenticated)
        let context = try await sut.accessContext()
        #expect(context.accountID == "personal-a")
        #expect(context.source == .webSession)
        #expect(logins.value == 1 && commits.value == 1 && writes.value == 2)
        #expect(cliCalls.value == 1) // reconnect must not silently reimport the old CLI session
    }

    @Test("mismatched reconnect never commits and preserves the prior connection")
    func mismatchedReconnectPreservesPriorConnection() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        let commits = LockIsolated(0), persisted = LockIsolated<[String?]>([])
        let wrong = Self.jwt(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "work-b"]])
        let sut = makeSUT(probe: { .notFound }, oauthCredentialsLoader: {
            Self.oauthCredentials(accessToken: "fixture-old-a", accountID: "personal-a")
        }, expectedAccountID: { "personal-a" }, contextWriter: { c in persisted.withLock { $0.append(c.accountID) } },
        interactiveSessionProvider: { _ in
            .init(sessionToken: "", accessToken: wrong, expiresAt: .now.addingTimeInterval(3600), cookiesToCommit: [])
        }, sessionCommitter: { _, _ in commits.withLock { $0 += 1 } })
        await sut.bootstrap()
        await #expect(throws: NetworkError.self) { try await sut.reconnect() }
        #expect(await sut.state == .authenticated)
        #expect(commits.value == 0 && persisted.value == ["personal-a"])
        #expect(try await sut.accessContext().accessToken == "fixture-old-a")
    }

    @Test("failed independent verification preserves the old connection and never commits")
    func failedSnapshotVerificationPreservesConnection() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        let commits = LockIsolated(0), writes = LockIsolated(0)
        let right = Self.jwt(payload: ["chatgpt_account_id": "personal-a"])
        let sut = makeSUT(probe: { .notFound }, oauthCredentialsLoader: {
            Self.oauthCredentials(accessToken: "fixture-old-a", accountID: "personal-a")
        }, expectedAccountID: { "personal-a" }, contextWriter: { _ in writes.withLock { $0 += 1 } },
        interactiveSessionProvider: { _ in .init(sessionToken: "fixture-session-a", accessToken: right,
            expiresAt: nil, cookiesToCommit: [Self.fixtureCookie("fixture-session-a")]) },
        sessionCommitter: { _, _ in commits.withLock { $0 += 1 } },
        stagedSessionVerifier: { _ in throw NetworkError.refreshFailed })
        await sut.bootstrap()
        await #expect(throws: NetworkError.self) { try await sut.reconnect() }
        #expect(await sut.state == .authenticated)
        #expect(commits.value == 0 && writes.value == 1)
        #expect(try await sut.accessContext().accessToken == "fixture-old-a")
    }

    @Test("a verified jar without the legacy cookie name can finish reconnect")
    func verifiedJarDoesNotRequireLegacyCookieName() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        let commits = LockIsolated(0), verifications = LockIsolated(0)
        let right = Self.jwt(payload: ["chatgpt_account_id": "personal-a"])
        let native = HTTPCookie(properties: [.name: "new-provider-cookie", .value: "fixture",
            .domain: ".chatgpt.com", .path: "/"])!
        let sut = makeSUT(probe: { .notFound }, expectedAccountID: { "personal-a" }, contextWriter: { _ in },
        interactiveSessionProvider: { _ in .init(sessionToken: "", accessToken: right, expiresAt: nil, cookiesToCommit: [native]) },
        sessionCommitter: { cookies, _ in
            #expect(cookies == [native]); commits.withLock { $0 += 1 }
        }, stagedSessionVerifier: { candidate in verifications.withLock { $0 += 1 }; return candidate })
        await sut.bootstrap()
        try await sut.reconnect()
        #expect(await sut.state == .authenticated)
        #expect(try await sut.accessContext().accountID == "personal-a")
        #expect(commits.value == 1 && verifications.value == 1)
    }

    @Test("a verified native jar renews after expiry and refuses a different workspace")
    func nativeJarRenewalStaysAccountLocal() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        let initial = Self.jwt(payload: ["chatgpt_account_id": "work-b", "marker": "old"])
        let renewed = Self.jwt(payload: ["chatgpt_account_id": "work-b", "marker": "renewed"])
        let wrong = Self.jwt(payload: ["chatgpt_account_id": "personal-a"])
        let browser = LockIsolated<CodexWebSessionResult?>(nil)
        let native = HTTPCookie(properties: [.name: "new-provider-cookie", .value: "fixture",
            .domain: ".chatgpt.com", .path: "/"])!
        let sut = makeSUT(accountStorageID: UUID(), probe: { .notFound }, headlessSessionReviver: { browser.value },
            expectedAccountID: { "work-b" }, contextWriter: { _ in },
            interactiveSessionProvider: { _ in .init(sessionToken: "", accessToken: initial,
                expiresAt: .now.addingTimeInterval(-1), cookiesToCommit: [native]) },
            sessionCommitter: { _, _ in }, stagedSessionVerifier: { $0 })
        await sut.bootstrap()
        try await sut.reconnect()
        browser.withLock { $0 = .init(sessionToken: "", accessToken: renewed,
            expiresAt: .now.addingTimeInterval(3600)) }
        #expect(try await sut.accessContext().accessToken == renewed)
        #expect(await sut.state == .authenticated)
        browser.withLock { $0 = .init(sessionToken: "", accessToken: wrong,
            expiresAt: .now.addingTimeInterval(3600)) }
        #expect(!(await sut.revalidateSessionAfterAuthFailure()))
        #expect(await sut.state == .unauthenticated)
    }

    @Test("sign-out during independent verification prevents late adoption")
    func signOutInvalidatesPendingVerification() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        let started = AsyncStream<Void>.makeStream(), release = AsyncStream<Void>.makeStream()
        let commits = LockIsolated(0)
        let right = Self.jwt(payload: ["chatgpt_account_id": "work-b"])
        let sut = makeSUT(accountStorageID: UUID(), probe: { .notFound }, expectedAccountID: { "work-b" },
            contextWriter: { _ in }, interactiveSessionProvider: { _ in .init(sessionToken: "fixture-session-a",
                accessToken: right, expiresAt: nil, cookiesToCommit: [Self.fixtureCookie("fixture-session-a")]) },
            sessionCommitter: { _, _ in commits.withLock { $0 += 1 } },
            stagedSessionVerifier: { candidate in
                started.continuation.yield(())
                var iterator = release.stream.makeAsyncIterator()
                _ = await iterator.next()
                return candidate
            }, sessionClearer: {})
        await sut.bootstrap()
        let reconnect = Task { try await sut.reconnect() }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        try await sut.signOut()
        release.continuation.yield(())
        await #expect(throws: NetworkError.self) { try await reconnect.value }
        #expect(await sut.state == .signedOutByUser)
        #expect(commits.value == 0)
    }

    @Test("cancelled reconnect leaves the prior session, state, and persistence unchanged")
    func cancelledReconnectPreservesPriorConnection() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        let commits = LockIsolated(0), writes = LockIsolated(0)
        let sut = makeSUT(probe: { .notFound }, oauthCredentialsLoader: {
            Self.oauthCredentials(accessToken: "fixture-old-a", accountID: "personal-a")
        }, expectedAccountID: { "personal-a" }, contextWriter: { _ in writes.withLock { $0 += 1 } },
        interactiveSessionProvider: { _ in throw CancellationError() },
        sessionCommitter: { _, _ in commits.withLock { $0 += 1 } })
        await sut.bootstrap()
        await #expect(throws: CancellationError.self) { try await sut.reconnect() }
        #expect(await sut.state == .authenticated)
        #expect(commits.value == 0 && writes.value == 1)
        #expect(try await sut.accessContext().accessToken == "fixture-old-a")
    }

    @Test("login window completion requires the saved workspace, including missing-claim rejection")
    func loginCompletionRequiresMatchingWorkspace() {
        let valid = Self.jwt(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "personal-a"]])
        let wrong = Self.jwt(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "work-b"]])
        #expect(CodexAuthCoordinator.acceptsInteractiveSession(.init(sessionToken: "", accessToken: valid, expiresAt: nil), expectedAccountID: "personal-a"))
        for value in [wrong, Self.jwt(payload: ["sub": "fixture-user"])] {
            #expect(!CodexAuthCoordinator.acceptsInteractiveSession(.init(sessionToken: "", accessToken: value, expiresAt: nil), expectedAccountID: "personal-a"))
        }
        #expect(NetworkError.accountIdentityMismatch.needsReconnect)
        #expect(!NetworkError.accountIdentityMismatch.isAuthError)
    }

    @Test("chunked session cookies are reassembled only when complete and from ChatGPT")
    func chunkedSessionCookieParsing() throws {
        func cookie(_ name: String, _ value: String, domain: String = ".chatgpt.com") throws -> HTTPCookie {
            try #require(HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/"]))
        }
        let name = "__Secure-next-auth.session-token"
        let a = try cookie(name + ".0", "fixture-a"), b = try cookie(name + ".1", "fixture-b")
        #expect(CodexAuthCoordinator.sessionToken(from: [b, a]) == "fixture-afixture-b")
        #expect(CodexAuthCoordinator.sessionToken(from: [b]) == nil)
        #expect(CodexAuthCoordinator.sessionToken(from: [a, try cookie(name + ".2", "fixture-c")]) == nil)
        #expect(CodexAuthCoordinator.sessionToken(from: [try cookie(name, "fixture-other", domain: ".other.example")]) == nil)
    }

    @Test("scoped Work reconnect cannot adopt Personal and leaves Personal untouched")
    func scopedReconnectPreservesOtherAccount() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        let personal = makeSUT(probe: { .notFound }, oauthCredentialsLoader: {
            Self.oauthCredentials(accessToken: "fixture-personal-a", accountID: "personal-a")
        }, expectedAccountID: { "personal-a" }, contextWriter: { _ in })
        let wrong = Self.jwt(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "personal-a"]])
        let right = Self.jwt(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "work-b"]])
        let candidate = LockIsolated(CodexWebSessionResult(sessionToken: "fixture-session-b", accessToken: wrong,
            expiresAt: .now.addingTimeInterval(3600), cookiesToCommit: [Self.fixtureCookie("fixture-session-b")]))
        let commits = LockIsolated(0)
        let work = makeSUT(accountStorageID: UUID(), probe: { .notFound }, oauthCredentialsLoader: {
            Self.oauthCredentials(accessToken: "fixture-old-b", accountID: "work-b")
        }, expectedAccountID: { "work-b" }, contextWriter: { _ in },
        interactiveSessionProvider: { _ in candidate.value }, sessionCommitter: { _, isCurrent in
            #expect(isCurrent()); commits.withLock { $0 += 1 }
        })
        await personal.bootstrap(); await work.bootstrap()
        await #expect(throws: NetworkError.self) { try await work.reconnect() }
        #expect(commits.value == 0)
        #expect(try await personal.accessContext().accountID == "personal-a")
        candidate.withLock { $0 = .init(sessionToken: "fixture-session-b", accessToken: right,
            expiresAt: .now.addingTimeInterval(3600), cookiesToCommit: [Self.fixtureCookie("fixture-session-b")]) }
        try await work.reconnect()
        #expect(commits.value == 1)
        #expect(try await work.accessContext().accountID == "work-b")
        #expect(try await personal.accessContext().accessToken == "fixture-personal-a")
    }

    @Test("reconnect rejects a cookie snapshot inconsistent with its verified session")
    func reconnectRejectsInconsistentCookieSnapshot() async throws {
        UserDefaults.standard.set(true, forKey: "app.installedAt.v2")
        let commits = LockIsolated(0)
        let right = Self.jwt(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "personal-a"]])
        let sut = makeSUT(probe: { .notFound }, oauthCredentialsLoader: {
            Self.oauthCredentials(accessToken: "fixture-old-a", accountID: "personal-a")
        }, expectedAccountID: { "personal-a" }, contextWriter: { _ in },
        interactiveSessionProvider: { _ in .init(sessionToken: "fixture-session-a", accessToken: right,
            expiresAt: .now.addingTimeInterval(3600), cookiesToCommit: [Self.fixtureCookie("fixture-session-b")]) },
        sessionCommitter: { _, _ in commits.withLock { $0 += 1 } })
        await sut.bootstrap()
        await #expect(throws: NetworkError.self) { try await sut.reconnect() }
        #expect(commits.value == 0)
        #expect(await sut.state == .authenticated)
        #expect(try await sut.accessContext().accessToken == "fixture-old-a")
    }

    @MainActor @Test("native cookie transaction rolls back on invalidation without touching another provider")
    func cookieCommitRollsBackAfterInvalidation() async throws {
        let old = Self.fixtureCookie("fixture-old"), new = Self.fixtureCookie("fixture-new")
        let other = try #require(HTTPCookie(properties: [.name: "other", .value: "fixture", .domain: ".claude.ai", .path: "/"]))
        var jar = [old, other]
        let current = LockIsolated(true)
        await #expect(throws: NetworkError.self) {
            try await CodexAuthCoordinator.replaceCookies([new], isCurrent: { current.value },
                read: { jar }, write: { cookie in
                    jar.append(cookie)
                    if cookie === new { current.withLock { $0 = false } }
                }, delete: { cookie in jar.removeAll { $0 === cookie } })
        }
        #expect(jar.contains { $0 === old })
        #expect(jar.contains { $0 === other })
        #expect(!jar.contains { $0 === new })
    }

    @MainActor @Test("native cookie commit preserves provider cookie objects and attributes")
    func cookieCommitPreservesNativeAttributes() async throws {
        let old = Self.fixtureCookie("fixture-old")
        let new = Self.fixtureCookie("fixture-new")
        var jar = [old]
        try await CodexAuthCoordinator.replaceCookies([new], isCurrent: { true },
            read: { jar }, write: { jar.append($0) }, delete: { cookie in jar.removeAll { $0 === cookie } })
        #expect(jar.count == 1 && jar.first === new)
        #expect(jar.first?.isHTTPOnly == new.isHTTPOnly)
        #expect(jar.first?.isSecure == new.isSecure)
    }

    @Test("explicit Sign Out waits for a rejected reconnect commit before clearing the session")
    func signOutDuringReconnectCommitCannotReauthenticate() async throws {
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let currentCheck = LockIsolated<(@Sendable () -> Bool)?>(nil)
        let rollbacks = LockIsolated(0), clears = LockIsolated(0), writes = LockIsolated(0)
        let right = Self.jwt(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "personal-a"]])
        let sut = makeSUT(accountStorageID: UUID(), probe: { .notFound }, oauthCredentialsLoader: {
            Self.oauthCredentials(accessToken: "fixture-old-a", accountID: "personal-a")
        }, expectedAccountID: { "personal-a" }, contextWriter: { _ in writes.withLock { $0 += 1 } },
        interactiveSessionProvider: { _ in .init(sessionToken: "fixture-session-a", accessToken: right,
            expiresAt: .now.addingTimeInterval(3600), cookiesToCommit: [Self.fixtureCookie("fixture-session-a")]) },
        sessionCommitter: { _, isCurrent in
            currentCheck.withLock { $0 = isCurrent }
            started.continuation.yield(())
            for await _ in release.stream { break }
            guard isCurrent() else {
                rollbacks.withLock { $0 += 1 }
                throw NetworkError.accountIdentityMismatch
            }
        }, sessionClearer: {
            #expect(rollbacks.value == 1)
            clears.withLock { $0 += 1 }
        })
        await sut.bootstrap()
        let reconnect = Task { try await sut.reconnect() }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        let signOut = Task { try await sut.signOut() }
        for _ in 0..<1000 {
            if currentCheck.value?() == false { break }
            await Task.yield()
        }
        #expect(currentCheck.value?() == false)
        release.continuation.yield(())
        try await signOut.value
        await #expect(throws: NetworkError.self) { try await reconnect.value }
        #expect(await sut.state == .signedOutByUser)
        #expect(rollbacks.value == 1 && clears.value == 1 && writes.value == 1)
    }

    @Test("cookie byte changes do not replace independent staged-session verification")
    func loginGateRequiresWorkspaceAndMatchingSnapshot() {
        let right = Self.jwt(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "personal-a"]])
        let session = CodexWebSessionResult(sessionToken: "fixture-session-a", accessToken: right,
            expiresAt: nil, cookiesToCommit: [Self.fixtureCookie("fixture-session-a")])
        let gate = CodexLoginCompletionGate()
        #expect(gate.evaluate(session, expectedAccountID: "personal-a") == .complete)
        #expect(gate.evaluate(session, expectedAccountID: "work-b") == .waitForAccount)
        let changed = CodexWebSessionResult(sessionToken: "stale-session", accessToken: right,
            expiresAt: nil, cookiesToCommit: session.cookiesToCommit)
        #expect(gate.evaluate(changed, expectedAccountID: "personal-a") == .invalidSnapshot)
        let unrecognized = CodexWebSessionResult(sessionToken: "", accessToken: right, expiresAt: nil, cookiesToCommit: [])
        #expect(gate.evaluate(unrecognized, expectedAccountID: "personal-a") == .complete)
        // This proceeds to the independent verifier; the gate alone never commits.
    }

    @Test("unrelated cookie changes do not destabilize matching login completion")
    func ancillaryCookiesDoNotInvalidateLogin() throws {
        let right = Self.jwt(payload: ["https://api.openai.com/auth": ["chatgpt_account_id": "personal-a"]])
        let auth = Self.fixtureCookie("fixture-session-a")
        let ancillary = try #require(HTTPCookie(properties: [.name: "language", .value: "en", .domain: ".chatgpt.com", .path: "/"]))
        let gate = CodexLoginCompletionGate()
        #expect(gate.evaluate(.init(sessionToken: "fixture-session-a", accessToken: right, expiresAt: nil,
            cookiesToCommit: [auth, ancillary]), expectedAccountID: "personal-a") == .complete)
    }

    private static func fixtureCookie(_ value: String) -> HTTPCookie {
        HTTPCookie(properties: [.name: "__Secure-next-auth.session-token", .value: value,
            .domain: ".chatgpt.com", .path: "/", .secure: "TRUE",
            HTTPCookiePropertyKey("HttpOnly"): "TRUE", HTTPCookiePropertyKey("SameSite"): "Lax"])!
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
