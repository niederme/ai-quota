import Foundation
import WebKit
import AppKit
import os

// MARK: - Probe types

public enum CodexProbeResult: Sendable {
    case found(sessionToken: String)
    case notFound
}

public enum CodexAuthSource: String, Codable, Sendable, Equatable {
    case codexOAuth
    case webSession
    case unknown
}

public struct CodexWebSessionResult: Sendable, Equatable {
    public let sessionToken: String
    public let accessToken: String
    public let expiresAt: Date?
    /// Present only for an explicit reconnect staged in an ephemeral browser.
    public let cookiesToCommit: [HTTPCookie]?

    public init(sessionToken: String, accessToken: String, expiresAt: Date?, cookiesToCommit: [HTTPCookie]? = nil) {
        self.sessionToken = sessionToken
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.cookiesToCommit = cookiesToCommit
    }
}

public struct CodexAccessContext: Sendable, Equatable {
    public let accessToken: String
    public let accountID: String?
    public let source: CodexAuthSource

    public init(accessToken: String, accountID: String?, source: CodexAuthSource) {
        self.accessToken = accessToken
        self.accountID = accountID
        self.source = source
    }
}

// MARK: - CodexAuthCoordinator

public actor CodexAuthCoordinator {

    private static let signedOutKey    = "codex.signedOutByUser"
    private static let freshInstallKey = "app.installedAt.v2"
    static let loginURL = URL(string: "https://chatgpt.com/auth/login")!

    public private(set) var state: AuthState = .unknown
    private var continuations: [UUID: AsyncStream<AuthState>.Continuation] = [:]

    // JWT cache — owned entirely by the coordinator
    private var cachedAccessToken: String?
    private var tokenExpiresAt: Date?
    private var accountID: String?
    private var authSource: CodexAuthSource?
    private var oauthDisabledForSession = false
    private var contextGeneration = 0

    private let logger = Logger(subsystem: "ai.quota", category: "codex-coord")

    /// Stable app-owned account identifier. A scoped coordinator uses an
    /// independent persistent WebKit data store and credential snapshot.
    public let accountStorageID: UUID?

    public typealias SessionProbe = @Sendable () async -> CodexProbeResult
    public typealias HeadlessSessionReviver = @Sendable () async -> CodexWebSessionResult?
    public typealias AccessTokenRefresher = @Sendable (_ sessionToken: String) async throws -> (token: String, expiresAt: Date?)
    public typealias OAuthCredentialsLoader = @Sendable () throws -> CodexOAuthCredentials
    public typealias InteractiveSessionProvider = @Sendable (_ expectedAccountID: String?) async throws -> CodexWebSessionResult
    public typealias SessionCommitter = @Sendable (_ cookies: [HTTPCookie], _ isCurrent: @escaping @Sendable () -> Bool) async throws -> Void
    public typealias StagedSessionVerifier = @Sendable (_ session: CodexWebSessionResult) async throws -> CodexWebSessionResult
    private let probe: SessionProbe
    private let headlessSessionReviver: HeadlessSessionReviver
    private let tokenRefresher: AccessTokenRefresher
    private let oauthCredentialsLoader: OAuthCredentialsLoader
    private let expectedAccountID: @Sendable () -> String?
    private let contextWriter: @Sendable (SharedCodexAuthContext) -> Void
    private let interactiveSessionProvider: InteractiveSessionProvider?
    private let sessionCommitter: SessionCommitter
    private let stagedSessionVerifier: StagedSessionVerifier
    private let sessionClearer: (@Sendable () async -> Void)?
    private let commitValidity = OSAllocatedUnfairLock<UUID?>(initialState: nil)
    private var pendingCookieCommit: Task<Void, Error>?
    private var pendingCookieCommitID: UUID?

    public init(
        accountStorageID: UUID? = nil,
        probe: SessionProbe? = nil,
        headlessSessionReviver: HeadlessSessionReviver? = nil,
        tokenRefresher: AccessTokenRefresher? = nil,
        oauthCredentialsLoader: OAuthCredentialsLoader? = nil,
        expectedAccountID: (@Sendable () -> String?)? = nil,
        contextWriter: (@Sendable (SharedCodexAuthContext) -> Void)? = nil,
        interactiveSessionProvider: InteractiveSessionProvider? = nil,
        sessionCommitter: SessionCommitter? = nil,
        stagedSessionVerifier: StagedSessionVerifier? = nil,
        sessionClearer: (@Sendable () async -> Void)? = nil
    ) {
        self.accountStorageID = accountStorageID
        self.interactiveSessionProvider = interactiveSessionProvider
        self.stagedSessionVerifier = stagedSessionVerifier ?? { try await Self.verifyStagedSession($0) }
        self.sessionClearer = sessionClearer
        self.sessionCommitter = sessionCommitter ?? { cookies, isCurrent in
            try await Self.commitStagedCookies(cookies, for: accountStorageID, isCurrent: isCurrent)
        }
        self.contextWriter = contextWriter ?? { context in
            if let accountStorageID {
                SharedAuthContextStore.saveCodex(context, forAccountID: accountStorageID.uuidString)
            } else {
                SharedAuthContextStore.saveCodex(context)
            }
        }
        self.expectedAccountID = expectedAccountID ?? {
            let accounts = AccountRegistry.accounts(for: .codex)
            if let accountStorageID {
                return accounts.first { $0.id == accountStorageID.uuidString }?.workspaceID
            }
            return accounts.first { $0.connectionKind == .legacyPrimary }?.workspaceID
        }
        self.probe = probe ?? CodexAuthCoordinator.wkProbe(for: accountStorageID)
        self.headlessSessionReviver = headlessSessionReviver ?? CodexAuthCoordinator.headlessWebSessionReviver(for: accountStorageID)
        self.tokenRefresher = tokenRefresher ?? CodexAuthCoordinator.defaultTokenRefresher
        self.oauthCredentialsLoader = oauthCredentialsLoader ?? {
            // Codex CLI credentials are a process-global identity. Reusing them
            // for every connected account would silently collapse all scoped
            // coordinators onto that one identity. A caller may still provide
            // an explicitly account-scoped loader.
            guard accountStorageID == nil else { throw CodexOAuthCredentialsError.notFound }
            return try CodexOAuthCredentialsStore.loadUsable()
        }
    }

    private var signedOutDefaultsKey: String {
        guard let accountStorageID else { return Self.signedOutKey }
        return "\(Self.signedOutKey).\(accountStorageID.uuidString.lowercased())"
    }

    private var sessionTokenKey: String {
        guard let accountStorageID else { return "sessionToken" }
        return "sessionToken.\(accountStorageID.uuidString.lowercased())"
    }

    // MARK: - State stream

    public nonisolated var stateStream: AsyncStream<AuthState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(continuation: continuation, id: id) }
            continuation.onTermination = { _ in Task { await self.unregister(id: id) } }
        }
    }

    private func register(continuation: AsyncStream<AuthState>.Continuation, id: UUID) {
        continuations[id] = continuation
        continuation.yield(state)
    }

    private func unregister(id: UUID) { continuations.removeValue(forKey: id) }

    private func transition(to newState: AuthState) {
        state = newState
        logger.info("[CodexCoord] → \(String(describing: newState), privacy: .public)")
        for c in continuations.values { c.yield(newState) }
    }

    // MARK: - Bootstrap

    public func bootstrap() async {
        guard state == .unknown else { return }

        await clearStateIfFreshInstall()

        if UserDefaults.standard.bool(forKey: signedOutDefaultsKey) {
            transition(to: .signedOutByUser)
            return
        }

        transition(to: .restoringSession)
        if restoreFromOAuthCredentials() {
            transition(to: .authenticated)
            return
        }

        let operationGeneration = contextGeneration
        let operationExpected = expectedAccountID()
        let result = await withProbeTimeout(probe)
        guard state == .restoringSession, operationGeneration == contextGeneration,
              expectedAccountID() == operationExpected else { return }
        if case .found(let token) = result, await restoreFromSessionToken(token) {
            transition(to: .authenticated)
            return
        }
        // The cookie probe can miss an otherwise usable page session (for
        // example, chunked cookies). Existing scoped accounts need the same
        // page-context recovery as the primary, using only their own store.
        let generation = contextGeneration
        let expected = expectedAccountID()
        if accountStorageID != nil, expected != nil,
           let revived = await headlessSessionReviver(), generation == contextGeneration,
           expectedAccountID() == expected, state == .restoringSession,
           restoreFromWebSession(revived) {
            transition(to: .authenticated)
            return
        }
        if state == .restoringSession { transition(to: .unauthenticated) }
    }

    // MARK: - signIn()

    public func signIn() async throws {
        switch state {
        case .unauthenticated, .signedOutByUser: break
        default: throw AuthCoordinatorError.invalidTransition(from: state)
        }
        if restoreFromOAuthCredentials() {
            UserDefaults.standard.removeObject(forKey: signedOutDefaultsKey)
            transition(to: .authenticated)
            return
        }
        try await interactiveSignIn(preserveExistingSession: false)
    }

    /// Explicit reconnect accepts an authenticated-but-unverified connection.
    /// It never signs out first or silently reimports process-wide credentials.
    public func reconnect() async throws {
        switch state {
        case .authenticated, .unauthenticated, .signedOutByUser: break
        default: throw AuthCoordinatorError.invalidTransition(from: state)
        }
        try await interactiveSignIn(preserveExistingSession: true)
    }

    static func acceptsInteractiveSession(_ session: CodexWebSessionResult, expectedAccountID: String?) -> Bool {
        guard let expectedAccountID, !expectedAccountID.isEmpty else { return true }
        return CodexOAuthCredentialsStore.jwtAccountID(session.accessToken) == expectedAccountID
    }

    private func interactiveSignIn(preserveExistingSession: Bool) async throws {
        let previousState = state
        let generation = contextGeneration
        let expected = expectedAccountID()
        transition(to: .signingIn)
        do {
            let result: CodexWebSessionResult
            if let interactiveSessionProvider {
                let candidate = try await interactiveSessionProvider(expected)
                guard generation == contextGeneration, state == .signingIn, expectedAccountID() == expected,
                      Self.acceptsInteractiveSession(candidate, expectedAccountID: expected) else {
                    throw NetworkError.accountIdentityMismatch
                }
                result = candidate.cookiesToCommit == nil ? candidate : try await stagedSessionVerifier(candidate)
            } else {
                let login = try await runLoginWindow(expectedAccountID: expected, preserveExistingSession: preserveExistingSession)
                result = .init(sessionToken: login.sessionToken, accessToken: login.accessToken,
                               expiresAt: login.expiresAt, cookiesToCommit: login.cookiesToCommit)
            }
            guard generation == contextGeneration, state == .signingIn,
                  expectedAccountID() == expected,
                  Self.acceptsInteractiveSession(result, expectedAccountID: expected) else {
                throw NetworkError.accountIdentityMismatch
            }
            if let cookies = result.cookiesToCommit {
                guard (Self.sessionToken(from: cookies) ?? "") == result.sessionToken else {
                    throw NetworkError.accountIdentityMismatch
                }
                let commitID = UUID()
                let validity = commitValidity
                let expectedLoader = expectedAccountID
                let committer = sessionCommitter
                validity.withLock { $0 = commitID }
                let task = Task {
                    try await committer(cookies, {
                        validity.withLock { $0 == commitID } && expectedLoader() == expected
                    })
                }
                pendingCookieCommit = task
                pendingCookieCommitID = commitID
                defer {
                    validity.withLock { if $0 == commitID { $0 = nil } }
                    if pendingCookieCommitID == commitID {
                        pendingCookieCommit = nil
                        pendingCookieCommitID = nil
                    }
                }
                try await task.value
                guard generation == contextGeneration, state == .signingIn,
                      expectedAccountID() == expected else { throw NetworkError.accountIdentityMismatch }
            }
            if !result.sessionToken.isEmpty {
                KeychainStore.save(result.sessionToken, forKey: sessionTokenKey)
            } else if result.cookiesToCommit != nil {
                // The verified browser jar is now authoritative. Do not later
                // refresh using an obsolete credential from the previous jar.
                KeychainStore.delete(forKey: sessionTokenKey)
            }
            cachedAccessToken = result.accessToken
            tokenExpiresAt = result.expiresAt ?? Date.now.addingTimeInterval(86400)
            accountID = CodexOAuthCredentialsStore.jwtAccountID(result.accessToken)
            authSource = .webSession
            if preserveExistingSession { oauthDisabledForSession = true }
            persistSharedAuthContext(sessionToken: result.sessionToken)
            UserDefaults.standard.removeObject(forKey: signedOutDefaultsKey)
            transition(to: .authenticated)
        } catch {
            if generation == contextGeneration, state == .signingIn {
                transition(to: previousState)
            }
            throw error
        }
    }

    /// Best-effort recovery for already-enrolled installs that lose app-side
    /// Codex state after an app replacement. This mirrors the non-UI sign-in
    /// sources, including a headless WebKit page-context session fetch.
    @discardableResult
    public func restoreWithoutPromptIfPossible(allowSignedOutByUser: Bool = false) async -> Bool {
        logger.notice("[CodexRecovery] requested state=\(String(describing: self.state), privacy: .public) allowSignedOutByUser=\(allowSignedOutByUser)")
        switch state {
        case .authenticated:
            logger.notice("[CodexRecovery] already authenticated")
            return true
        case .unauthenticated:
            break
        case .signedOutByUser where allowSignedOutByUser:
            break
        default:
            logger.notice("[CodexRecovery] skipped unsupported state=\(String(describing: self.state), privacy: .public)")
            return false
        }

        logger.notice("[CodexRecovery] trying Codex OAuth file")
        if restoreFromOAuthCredentialsForRecovery() {
            UserDefaults.standard.removeObject(forKey: signedOutDefaultsKey)
            transition(to: .authenticated)
            return true
        }

        logger.notice("[CodexRecovery] trying WebKit session probe")
        let operationGeneration = contextGeneration
        let operationExpected = expectedAccountID()
        let operationState = state
        let probeResult = await withProbeTimeout(probe)
        guard operationGeneration == contextGeneration, state == operationState,
              expectedAccountID() == operationExpected else { return false }
        if case .found(let token) = probeResult {
            if await restoreFromSessionToken(token) {
                logger.notice("[CodexRecovery] WebKit probe restored session")
                UserDefaults.standard.removeObject(forKey: signedOutDefaultsKey)
                transition(to: .authenticated)
                return true
            }
            logger.notice("[CodexRecovery] WebKit probe token refresh failed")
        }

        switch probeResult {
        case .notFound:
            logger.notice("[CodexRecovery] WebKit probe did not find a Codex session")
        case .none:
            logger.notice("[CodexRecovery] WebKit probe timed out")
        case .found:
            break
        }

        logger.notice("[CodexRecovery] trying headless WebKit session revival")
        let generation = contextGeneration
        let expected = expectedAccountID()
        if let headlessResult = await headlessSessionReviver(), generation == contextGeneration,
           state == operationState, expectedAccountID() == expected, restoreFromWebSession(headlessResult) {
            logger.notice("[CodexRecovery] headless WebKit revival found sessionToken=\(!headlessResult.sessionToken.isEmpty, privacy: .public)")
            UserDefaults.standard.removeObject(forKey: signedOutDefaultsKey)
            transition(to: .authenticated)
            return true
        }

        logger.notice("[CodexRecovery] headless WebKit revival did not find a Codex session")
        return false
    }

    // MARK: - signOut()

    public func signOut() async throws {
        if state == .signingIn {
            commitValidity.withLock { $0 = nil }
            if let pendingCookieCommit { _ = try? await pendingCookieCommit.value }
        }
        switch state {
        case .unauthenticated, .signedOutByUser:
            return
        case .authenticated, .signingIn:
            break
        default:
            throw AuthCoordinatorError.invalidTransition(from: state)
        }

        transition(to: .signingOut)
        UserDefaults.standard.set(true, forKey: signedOutDefaultsKey)
        clearTokenCache()
        KeychainStore.delete(forKey: sessionTokenKey)
        clearPersistedSharedAuthContext()
        await clearWKCookies()
        clearURLSessionCookies()
        await verifyWKCookiesEmpty()
        transition(to: .signedOutByUser)
    }

    // MARK: - revalidateSessionAfterAuthFailure()

    @discardableResult
    public func revalidateSessionAfterAuthFailure() async -> Bool {
        guard state == .authenticated else { return false }

        if restoreFromOAuthCredentials() {
            return true
        }

        let generation = contextGeneration
        let expected = expectedAccountID()
        let result = await withProbeTimeout(probe)

        // Re-check: another transition may have run while probe was in flight.
        guard generation == contextGeneration, state == .authenticated, expectedAccountID() == expected else { return false }

        if case .found(let token) = result, await restoreFromSessionToken(token) { return true }
        guard generation == contextGeneration, state == .authenticated else { return false }
        if await refreshFromAccountBrowser() != nil { return true }
        guard generation == contextGeneration, state == .authenticated else { return false }
        // A failed or incomplete probe is not permission to erase the saved
        // session. Explicit sign-out/reset own destructive credential cleanup.
        clearTokenCache()
        transition(to: .unauthenticated)
        return false
    }

    // MARK: - reset()

    public func reset() async {
        // Invalidate and await a staged commit/rollback before destructive reset
        // so a late browser write cannot repopulate a deliberately reset store.
        commitValidity.withLock { $0 = nil }
        if let pendingCookieCommit { _ = try? await pendingCookieCommit.value }
        let deadline = Date.now.addingTimeInterval(30)
        while (state == .signingIn || state == .signingOut || state == .resetting),
              Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard state == .authenticated || state == .unauthenticated || state == .signedOutByUser else {
            logger.warning("[CodexCoord] reset: timed out waiting for in-flight transition to settle; forcing signedOutByUser")
            UserDefaults.standard.set(true, forKey: signedOutDefaultsKey)
            clearTokenCache()
            KeychainStore.delete(forKey: sessionTokenKey)
            clearPersistedSharedAuthContext()
            transition(to: .signedOutByUser)
            return
        }

        transition(to: .resetting)
        UserDefaults.standard.set(true, forKey: signedOutDefaultsKey)
        clearTokenCache()
        KeychainStore.delete(forKey: sessionTokenKey)
        clearPersistedSharedAuthContext()
        await clearWKCookies()
        clearURLSessionCookies()
        let verified = await verifyWKCookiesEmpty()
        if !verified { logger.warning("[CodexCoord] reset: WebKit teardown could not be fully verified") }
        transition(to: .signedOutByUser)
    }

    // MARK: - accessToken() (for OpenAIClient)

    public func accessToken() async throws -> String {
        let context = try await accessContext()
        return context.accessToken
    }

    public func accessContext() async throws -> CodexAccessContext {
        guard state == .authenticated else { throw NetworkError.notAuthenticated }

        if restoreFromOAuthCredentials() {
            guard let token = cachedAccessToken else { throw NetworkError.notAuthenticated }
            return CodexAccessContext(accessToken: token, accountID: accountID, source: .codexOAuth)
        }

        if let token = cachedAccessToken, let exp = tokenExpiresAt, exp.addingTimeInterval(-60) > .now,
           matchesExpectedAccount(accountID) {
            return CodexAccessContext(accessToken: token, accountID: accountID, source: authSource ?? .webSession)
        }
        let token = try await refreshAccessToken()
        return CodexAccessContext(accessToken: token, accountID: accountID, source: .webSession)
    }

    public func disableOAuthForSession() {
        oauthDisabledForSession = true
        if authSource == .codexOAuth {
            clearTokenCache()
        }
    }

    // MARK: - Private

    private func matchesExpectedAccount(_ candidate: String?) -> Bool {
        guard let expected = expectedAccountID(), !expected.isEmpty else { return true }
        return candidate == expected
    }

    private func clearTokenCache() {
        contextGeneration += 1
        commitValidity.withLock { $0 = nil }
        cachedAccessToken = nil
        tokenExpiresAt = nil
        accountID = nil
        authSource = nil
    }

    private func restoreFromOAuthCredentials() -> Bool {
        guard !oauthDisabledForSession else { return false }
        guard let credentials = try? oauthCredentialsLoader(),
              matchesExpectedAccount(credentials.accountID) else { return false }
        cachedAccessToken = credentials.accessToken
        tokenExpiresAt = credentials.expiresAt ?? Date.now.addingTimeInterval(3600)
        accountID = credentials.accountID
        authSource = .codexOAuth
        persistSharedAuthContext(sessionToken: "")
        return true
    }

    private func restoreFromOAuthCredentialsForRecovery() -> Bool {
        guard !oauthDisabledForSession else {
            logger.notice("[CodexRecovery] Codex OAuth file failed reason=disabledForSession")
            return false
        }
        do {
            let credentials = try oauthCredentialsLoader()
            guard matchesExpectedAccount(credentials.accountID) else {
                logger.notice("[CodexRecovery] OAuth candidate belongs to another workspace; preserving this account")
                return false
            }
            cachedAccessToken = credentials.accessToken
            tokenExpiresAt = credentials.expiresAt ?? Date.now.addingTimeInterval(3600)
            accountID = credentials.accountID
            authSource = .codexOAuth
            persistSharedAuthContext(sessionToken: "")
            logger.notice("[CodexRecovery] Codex OAuth file usable")
            return true
        } catch {
            logger.notice("[CodexRecovery] Codex OAuth file failed reason=\(Self.recoveryErrorDescription(error), privacy: .public)")
            return false
        }
    }

    private static func recoveryErrorDescription(_ error: Error) -> String {
        switch error {
        case CodexOAuthCredentialsError.notFound:
            return "notFound"
        case CodexOAuthCredentialsError.decodeFailed:
            return "decodeFailed"
        case CodexOAuthCredentialsError.missingTokens:
            return "missingTokens"
        case CodexOAuthCredentialsError.missingAccessToken:
            return "missingAccessToken"
        case CodexOAuthCredentialsError.expired:
            return "expired"
        default:
            return String(describing: error)
        }
    }

    private func restoreFromSessionToken(_ sessionToken: String) async -> Bool {
        guard !sessionToken.isEmpty else { return false }

        let generation = contextGeneration
        let expected = expectedAccountID()
        let operationState = state
        do {
            let refreshed = try await tokenRefresher(sessionToken)
            guard generation == contextGeneration, state == operationState, expectedAccountID() == expected,
                  matchesExpectedAccount(CodexOAuthCredentialsStore.jwtAccountID(refreshed.token)) else { return false }
            KeychainStore.save(sessionToken, forKey: sessionTokenKey)
            cachedAccessToken = refreshed.token
            tokenExpiresAt = refreshed.expiresAt ?? Date.now.addingTimeInterval(86400)
            accountID = CodexOAuthCredentialsStore.jwtAccountID(refreshed.token)
            authSource = .webSession
            persistSharedAuthContext(sessionToken: sessionToken)
            return true
        } catch {
            guard generation == contextGeneration else { return false }
            // Preserve any existing context on transient restoration failure.
            return false
        }
    }

    @discardableResult
    private func restoreFromWebSession(_ result: CodexWebSessionResult) -> Bool {
        guard matchesExpectedAccount(CodexOAuthCredentialsStore.jwtAccountID(result.accessToken)) else {
            logger.notice("[CodexRecovery] Web candidate belongs to another workspace; preserving this account")
            return false
        }
        if !result.sessionToken.isEmpty {
            KeychainStore.save(result.sessionToken, forKey: sessionTokenKey)
        }
        cachedAccessToken = result.accessToken
        tokenExpiresAt = result.expiresAt ?? Date.now.addingTimeInterval(86400)
        accountID = CodexOAuthCredentialsStore.jwtAccountID(result.accessToken)
        authSource = .webSession
        persistSharedAuthContext(sessionToken: result.sessionToken)
        return true
    }

    private func persistSharedAuthContext(sessionToken: String? = nil) {
        let effectiveSessionToken = sessionToken ?? KeychainStore.load(forKey: sessionTokenKey) ?? ""
        let context = SharedCodexAuthContext(
            sessionToken: effectiveSessionToken,
            accessToken: cachedAccessToken,
            accessTokenExpiresAt: tokenExpiresAt,
            accountID: accountID
        )
        contextWriter(context)
    }

    private func clearPersistedSharedAuthContext() {
        if let accountStorageID {
            SharedAuthContextStore.clearCodex(forAccountID: accountStorageID.uuidString)
        } else {
            SharedAuthContextStore.clearCodex()
        }
    }

    private func clearURLSessionCookies() {
        // Scoped coordinators never copy their browser cookies into the process
        // global jar, so signing one account out must leave that jar untouched.
        guard accountStorageID == nil else { return }
        for cookie in HTTPCookieStorage.shared.cookies ?? []
            where cookie.domain.contains("chatgpt.com") || cookie.domain.contains("openai.com") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private func clearWKCookies() async {
        if let sessionClearer { await sessionClearer(); return }
        let accountStorageID = self.accountStorageID
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                let dataStore = Self.websiteDataStore(for: accountStorageID)
                dataStore.httpCookieStore.getAllCookies { cookies in
                    let relevant = cookies.filter { $0.domain.contains("chatgpt.com") || $0.domain.contains("openai.com") }
                    guard !relevant.isEmpty else { cont.resume(); return }
                    let g = DispatchGroup()
                    for c in relevant { g.enter(); dataStore.httpCookieStore.delete(c) { g.leave() } }
                    g.notify(queue: .main) { cont.resume() }
                }
            }
        }
    }

    @discardableResult
    private func verifyWKCookiesEmpty() async -> Bool {
        if sessionClearer != nil { return true }
        let accountStorageID = self.accountStorageID
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            Task { @MainActor in
                Self.websiteDataStore(for: accountStorageID).httpCookieStore.getAllCookies { cookies in
                    let remaining = cookies.filter { $0.domain.contains("chatgpt.com") || $0.domain.contains("openai.com") }
                    cont.resume(returning: remaining.isEmpty)
                }
            }
        }
    }

    @discardableResult
    private func refreshAccessToken() async throws -> String {
        guard let sessionToken = KeychainStore.load(forKey: sessionTokenKey), !sessionToken.isEmpty else {
            if let refreshed = await refreshFromAccountBrowser() { return refreshed }
            throw NetworkError.notAuthenticated
        }
        let generation = contextGeneration
        let expected = expectedAccountID()
        let session = try await tokenRefresher(sessionToken)
        guard generation == contextGeneration, state == .authenticated, expectedAccountID() == expected,
              matchesExpectedAccount(CodexOAuthCredentialsStore.jwtAccountID(session.token)) else {
            throw NetworkError.accountIdentityMismatch
        }
        cachedAccessToken = session.token
        tokenExpiresAt = session.expiresAt ?? Date.now.addingTimeInterval(86400)
        accountID = CodexOAuthCredentialsStore.jwtAccountID(session.token)
        authSource = .webSession
        persistSharedAuthContext(sessionToken: sessionToken)
        return session.token
    }

    /// The account-local browser jar can remain valid when a provider changes
    /// its cookie names. Renew from that jar without importing another account.
    private func refreshFromAccountBrowser() async -> String? {
        let generation = contextGeneration
        let expected = expectedAccountID()
        let currentUser = cachedAccessToken.flatMap(CodexOAuthCredentialsStore.jwtUserID)
        guard state == .authenticated, let revived = await headlessSessionReviver(),
              generation == contextGeneration, state == .authenticated,
              expectedAccountID() == expected,
              Self.acceptsInteractiveSession(revived, expectedAccountID: expected),
              CodexOAuthCredentialsStore.jwtUserID(revived.accessToken) == currentUser,
              restoreFromWebSession(revived) else { return nil }
        return cachedAccessToken
    }

    private static func defaultTokenRefresher(_ sessionToken: String) async throws -> (token: String, expiresAt: Date?) {
        guard !sessionToken.isEmpty else { throw NetworkError.notAuthenticated }

        var req = URLRequest(url: URL(string: "https://chatgpt.com/api/auth/session")!)
        req.setValue("https://chatgpt.com", forHTTPHeaderField: "Referer")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        req.setValue("__Secure-next-auth.session-token=\(sessionToken)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
            throw NetworkError.refreshFailed
        }

        struct SessionResponse: Decodable { let accessToken: String; let expires: String? }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let session = try decoder.decode(SessionResponse.self, from: data)
        return (
            token: session.accessToken,
            expiresAt: Self.parseExpiryValue(session.expires)
        )
    }

    private static func parseExpiryValue(_ string: String?) -> Date? {
        guard let string else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: string)
    }

    private func withProbeTimeout(_ probe: @escaping SessionProbe) async -> CodexProbeResult? {
        await withCheckedContinuation { cont in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let probeTask = Task {
                let result = await probe()
                resumed.withLock { alreadyDone in
                    guard !alreadyDone else { return }
                    alreadyDone = true
                    cont.resume(returning: result)
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(10))
                resumed.withLock { alreadyDone in
                    guard !alreadyDone else { return }
                    alreadyDone = true
                    probeTask.cancel()
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func runLoginWindow(expectedAccountID: String?, preserveExistingSession: Bool) async throws -> CodexLoginResult {
        let accountStorageID = self.accountStorageID
        let verifier = stagedSessionVerifier
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let controller = CodexLoginWindowController(accountStorageID: accountStorageID,
                    expectedAccountID: expectedAccountID, preserveExistingSession: preserveExistingSession,
                    stagedSessionVerifier: verifier) { result in
                    continuation.resume(with: result)
                }
                controller.show()
            }
        }
    }

    private func clearStateIfFreshInstall() async {
        // Account containers are created after install and must not participate
        // in the app-wide legacy migration sentinel.
        guard accountStorageID == nil else { return }
        let sentinel = Self.freshInstallKey
        guard UserDefaults.standard.object(forKey: sentinel) == nil else { return }
        guard !(await AuthInstallState.isExistingInstall()) else {
            UserDefaults.standard.set(true, forKey: sentinel)
            return
        }
        KeychainStore.delete(forKey: sessionTokenKey)
        SharedDefaults.clearUsage()
        SharedDefaults.clearClaudeUsage()
        // Do not clear WebKit cookies here. A misclassified update/archive build
        // can otherwise destroy valid provider sessions before probes can use them.
        UserDefaults.standard.set(true, forKey: sentinel)
    }

    static func sessionToken(from cookies: [HTTPCookie]) -> String? {
        let cookies = cookies.filter {
            let domain = $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            return domain == "chatgpt.com" || domain.hasSuffix(".chatgpt.com")
        }
        let name = "__Secure-next-auth.session-token"
        if let exact = cookies.first(where: { $0.name == name }), !exact.value.isEmpty { return exact.value }
        let chunks = cookies.compactMap { cookie -> (Int, String)? in
            guard cookie.name.hasPrefix(name + "."),
                  let index = Int(cookie.name.dropFirst(name.count + 1)), index >= 0 else { return nil }
            return (index, cookie.value)
        }.sorted { $0.0 < $1.0 }
        guard !chunks.isEmpty, chunks.enumerated().allSatisfy({ $0.offset == $0.element.0 }) else { return nil }
        let value = chunks.map(\.1).joined()
        return value.isEmpty ? nil : value
    }

    /// Verify the frozen reconnect jar independently. A session fetch may renew
    /// opaque cookie bytes; observer generations are not identity evidence.
    static func verifyStagedSession(_ candidate: CodexWebSessionResult,
                                    session: URLSession? = nil) async throws -> CodexWebSessionResult {
        guard let cookies = candidate.cookiesToCommit,
              (sessionToken(from: cookies) ?? "") == candidate.sessionToken else {
            throw NetworkError.accountIdentityMismatch
        }
        let request = try stagedSessionRequest(cookies: cookies)
        let transport: URLSession
        if let session { transport = session } else { transport = stagedSessionTransport() }
        defer { if session == nil { transport.finishTasksAndInvalidate() } }
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url == request.url else { throw NetworkError.refreshFailed }
        guard http.statusCode == 200 else { throw NetworkError.httpError(statusCode: http.statusCode) }
        struct VerifiedSession: Decodable { let accessToken: String; let expires: String? }
        let verified = try JSONDecoder().decode(VerifiedSession.self, from: data)
        guard !verified.accessToken.isEmpty,
              let workspace = CodexOAuthCredentialsStore.jwtAccountID(candidate.accessToken), !workspace.isEmpty,
              CodexOAuthCredentialsStore.jwtAccountID(verified.accessToken) == workspace,
              CodexOAuthCredentialsStore.jwtUserID(candidate.accessToken) == CodexOAuthCredentialsStore.jwtUserID(verified.accessToken)
        else { throw NetworkError.accountIdentityMismatch }
        return .init(sessionToken: candidate.sessionToken, accessToken: verified.accessToken,
                     expiresAt: parseExpiryValue(verified.expires), cookiesToCommit: cookies)
    }

    static func stagedSessionRequest(cookies: [HTTPCookie], now: Date = .now) throws -> URLRequest {
        let url = URL(string: "https://chatgpt.com/api/auth/session")!
        let applicable = cookies.filter { cookie in
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            let path = cookie.path.isEmpty ? "/" : cookie.path
            let pathMatches = url.path == path || url.path.hasPrefix(path.hasSuffix("/") ? path : path + "/")
            return domain == url.host && pathMatches && (cookie.expiresDate == nil || cookie.expiresDate! > now)
        }
        guard !applicable.isEmpty,
              let header = HTTPCookie.requestHeaderFields(with: applicable)["Cookie"], !header.isEmpty else {
            throw NetworkError.notAuthenticated
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        request.setValue(header, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Referer")
        return request
    }

    static func stagedSessionTransport(configuration: URLSessionConfiguration = .ephemeral) -> URLSession {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration, delegate: CodexSessionRedirectBlocker(), delegateQueue: nil)
    }

    private static func wkProbe(for accountStorageID: UUID?) -> SessionProbe {
        {
            await withCheckedContinuation { cont in
                Task { @MainActor in
                    Self.websiteDataStore(for: accountStorageID).httpCookieStore.getAllCookies { cookies in
                        guard let token = Self.sessionToken(from: cookies) else {
                            cont.resume(returning: .notFound)
                            return
                        }
                        if accountStorageID == nil {
                            for c in cookies where c.domain.contains("chatgpt.com") || c.domain.contains("openai.com") {
                                HTTPCookieStorage.shared.setCookie(c)
                            }
                        }
                        cont.resume(returning: .found(sessionToken: token))
                    }
                }
            }
        }
    }

    private static func headlessWebSessionReviver(for accountStorageID: UUID?) -> HeadlessSessionReviver {
        {
            await withCheckedContinuation { continuation in
                Task { @MainActor in
                    let reviver = CodexHeadlessSessionReviver(accountStorageID: accountStorageID) { result in
                        continuation.resume(returning: result)
                    }
                    reviver.start()
                }
            }
        }
    }

    @MainActor
    private static func commitStagedCookies(_ cookies: [HTTPCookie], for accountStorageID: UUID?,
                                            isCurrent: @escaping @Sendable () -> Bool) async throws {
        let store = websiteDataStore(for: accountStorageID).httpCookieStore
        try await replaceCookies(cookies, isCurrent: isCurrent,
            read: { await store.allCookies() },
            write: { await store.setCookie($0) },
            delete: { await store.deleteCookie($0) })
    }

    @MainActor
    static func replaceCookies(_ cookies: [HTTPCookie], isCurrent: @escaping @Sendable () -> Bool,
                               read: @MainActor () async -> [HTTPCookie],
                               write: @MainActor (HTTPCookie) async throws -> Void,
                               delete: @MainActor (HTTPCookie) async throws -> Void) async throws {
        func isCodexDomain(_ cookie: HTTPCookie) -> Bool {
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            return domain == "chatgpt.com" || domain.hasSuffix(".chatgpt.com")
                || domain == "openai.com" || domain.hasSuffix(".openai.com")
        }
        guard cookies.contains(where: isCodexDomain) else { throw NetworkError.notAuthenticated }
        let old = await read().filter(isCodexDomain)
        guard isCurrent() else { throw NetworkError.accountIdentityMismatch }
        do {
            for cookie in old {
                guard isCurrent() else { throw NetworkError.accountIdentityMismatch }
                try await delete(cookie)
            }
            for cookie in cookies.filter(isCodexDomain) {
                guard isCurrent() else { throw NetworkError.accountIdentityMismatch }
                try await write(cookie) // preserve the original native attributes
            }
            guard isCurrent() else { throw NetworkError.accountIdentityMismatch }
        } catch {
            // Reset waits for this rollback before clearing the store. Other
            // invalidations restore the exact previous browser connection.
            for cookie in await read().filter(isCodexDomain) { try? await delete(cookie) }
            for cookie in old { try? await write(cookie) }
            throw error
        }
    }

    @MainActor
    private static func websiteDataStore(for accountStorageID: UUID?) -> WKWebsiteDataStore {
        accountStorageID.map(WKWebsiteDataStore.init(forIdentifier:)) ?? .default()
    }

    @MainActor
    fileprivate static func fetchSessionInPage(
        webView: WKWebView,
        includeCookies: Bool = false,
        completion: @escaping @MainActor (CodexWebSessionResult?) -> Void
    ) {
        webView.callAsyncJavaScript("""
            const controller = new AbortController();
            const timeout = setTimeout(() => controller.abort(), 15000);
            try {
                const r = await fetch('/api/auth/session', {
                    credentials: 'include',
                    cache: 'no-store',
                    signal: controller.signal,
                    headers: { 'Accept': 'application/json' }
                });
                if (!r.ok) return null;
                return await r.json();
            } catch(e) { return null; }
            finally { clearTimeout(timeout); }
        """, arguments: [:], in: nil, in: .page) { result in
            Task { @MainActor in
                guard case .success(let value) = result,
                      let dict = value as? [String: Any],
                      let accessToken = dict["accessToken"] as? String,
                      !accessToken.isEmpty
                else {
                    completion(nil)
                    return
                }

                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                let sessionToken = Self.sessionToken(from: cookies) ?? ""

                completion(CodexWebSessionResult(
                    sessionToken: sessionToken,
                    accessToken: accessToken,
                    expiresAt: parseExpiryValue(dict["expires"] as? String),
                    cookiesToCommit: includeCookies ? cookies : nil
                ))
            }
        }
    }
}

/// A frozen jar must never be forwarded to a redirect destination.
private final class CodexSessionRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

// MARK: - CodexLoginResult

/// Returned by CodexLoginWindowController — carries both the session token (for Keychain)
/// and the access token JWT. Staged reconnect results are independently verified
/// against their frozen cookie jar before this result reaches the coordinator.
struct CodexLoginResult {
    let sessionToken: String   // may be empty if the cookie wasn't found in WK store
    let accessToken: String    // JWT from /api/auth/session body
    let expiresAt: Date?
    let cookiesToCommit: [HTTPCookie]?

    init(sessionToken: String, accessToken: String, expiresAt: Date?, cookiesToCommit: [HTTPCookie]? = nil) {
        self.sessionToken = sessionToken
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.cookiesToCommit = cookiesToCommit
    }

    init(_ session: CodexWebSessionResult) {
        self.sessionToken = session.sessionToken
        self.accessToken = session.accessToken
        self.expiresAt = session.expiresAt
        self.cookiesToCommit = session.cookiesToCommit
    }
}

// MARK: - CodexHeadlessSessionReviver

@MainActor
private final class CodexHeadlessSessionReviver: NSObject {
    private var webView: WKWebView?
    private var timeoutTask: Task<Void, Never>?
    private var detectionRetryTask: Task<Void, Never>?
    private var selfRetain: CodexHeadlessSessionReviver?
    private var hasCompleted = false
    private var isFetchingSession = false
    private let onComplete: (@MainActor (CodexWebSessionResult?) -> Void)
    private let accountStorageID: UUID?
    private let logger = Logger(subsystem: "ai.quota", category: "codex-coord")

    init(accountStorageID: UUID?, onComplete: @escaping (@MainActor (CodexWebSessionResult?) -> Void)) {
        self.accountStorageID = accountStorageID
        self.onComplete = onComplete
    }

    func start() {
        selfRetain = self
        let config = WKWebViewConfiguration()
        config.websiteDataStore = accountStorageID.map(WKWebsiteDataStore.init(forIdentifier:)) ?? .default()
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            await MainActor.run { [weak self] in
                self?.complete(nil, reason: "timeout")
            }
        }
        webView.load(URLRequest(url: CodexAuthCoordinator.loginURL))
    }

    private func tryFetchSession() {
        guard !hasCompleted, !isFetchingSession, let webView else { return }
        guard let url = webView.url,
              url.host?.contains("chatgpt.com") == true
        else { return }
        if url.path.hasPrefix("/auth/") || url.path == "/login" {
            logger.notice("[CodexRecovery] headless WebKit landed on auth path=\(url.path, privacy: .public)")
        }
        isFetchingSession = true
        CodexAuthCoordinator.fetchSessionInPage(webView: webView) { [weak self] result in
            guard let self, !self.hasCompleted else { return }
            self.isFetchingSession = false
            if let result {
                self.complete(result, reason: "found")
            } else {
                self.scheduleDetectionRetry()
            }
        }
    }

    private func scheduleDetectionRetry() {
        guard detectionRetryTask == nil, !hasCompleted else { return }
        detectionRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run { [weak self] in
                guard let self, !self.hasCompleted else { return }
                self.detectionRetryTask = nil
                self.tryFetchSession()
            }
        }
    }

    private func complete(_ result: CodexWebSessionResult?, reason: String) {
        guard !hasCompleted else { return }
        hasCompleted = true
        logger.notice("[CodexRecovery] headless WebKit completed reason=\(reason, privacy: .public)")
        timeoutTask?.cancel()
        timeoutTask = nil
        detectionRetryTask?.cancel()
        detectionRetryTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        let callback = onComplete
        selfRetain = nil
        callback(result)
    }
}

@MainActor
extension CodexHeadlessSessionReviver: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tryFetchSession()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.notice("[CodexRecovery] headless WebKit navigation failed error=\(String(describing: error), privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logger.notice("[CodexRecovery] headless WebKit provisional navigation failed error=\(String(describing: error), privacy: .public)")
    }
}

struct CodexLoginCompletionGate {
    enum Decision: Equatable { case complete, waitForAccount, invalidSnapshot }

    func evaluate(_ session: CodexWebSessionResult, expectedAccountID: String?) -> Decision {
        guard CodexAuthCoordinator.acceptsInteractiveSession(session, expectedAccountID: expectedAccountID) else {
            return .waitForAccount
        }
        if let cookies = session.cookiesToCommit,
           (CodexAuthCoordinator.sessionToken(from: cookies) ?? "") != session.sessionToken {
            return .invalidSnapshot
        }
        return .complete
    }
}

// MARK: - CodexLoginWindowController

/// Presents a WKWebView login window and resolves with a CodexLoginResult.
///
/// Auth detection strategy: on every chatgpt.com page load (via didFinish) and on every
/// cookie change (via CodexCookieObserver), we call callAsyncJavaScript to fetch
/// /api/auth/session from the page context. A matching staged response is verified
/// against its frozen cookie jar before completion. No secondary navigation to the JSON endpoint is needed —
/// this avoids the "didFinish never fires for JSON endpoint" / "evaluateJavaScript hangs"
/// failure modes from the previous approach.
@MainActor
private final class CodexLoginWindowController: NSObject {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var popupWindows: [NSWindow] = []
    private var cookieObserver: CodexCookieObserver?
    private var hasCompleted = false
    private var isFetchingSession = false
    private let completionGate = CodexLoginCompletionGate()
    private let stagedSessionVerifier: CodexAuthCoordinator.StagedSessionVerifier
    private var selfRetain: CodexLoginWindowController?
    private let onComplete: (Result<CodexLoginResult, Error>) -> Void
    private let accountStorageID: UUID?
    private let expectedAccountID: String?
    private let preserveExistingSession: Bool
    private let logger = Logger(subsystem: "ai.quota", category: "codex-login")

    init(accountStorageID: UUID?, expectedAccountID: String?, preserveExistingSession: Bool,
         stagedSessionVerifier: @escaping CodexAuthCoordinator.StagedSessionVerifier,
         onComplete: @escaping (Result<CodexLoginResult, Error>) -> Void) {
        self.accountStorageID = accountStorageID
        self.expectedAccountID = expectedAccountID
        self.preserveExistingSession = preserveExistingSession
        self.stagedSessionVerifier = stagedSessionVerifier
        self.onComplete = onComplete
    }

    func show() {
        selfRetain = self
        let config = WKWebViewConfiguration()
        config.websiteDataStore = preserveExistingSession ? .nonPersistent()
            : accountStorageID.map(WKWebsiteDataStore.init(forIdentifier:)) ?? .default()

        let wv = WKWebView(frame: .init(x: 0, y: 0, width: 520, height: 680), configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        self.webView = wv

        let observer = CodexCookieObserver { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let wv = self.webView else { return }
                self.tryFetchSession(webView: wv)
            }
        }
        config.websiteDataStore.httpCookieStore.add(observer)
        self.cookieObserver = observer

        // Show the window immediately so the user gets visual feedback right away.
        // didFinish handles the two cases: login page (window already visible, user signs in)
        // or authenticated page (tryFetchSession completes and closes the window).
        showLoginWindow()
        wv.load(URLRequest(url: CodexAuthCoordinator.loginURL))
    }

    /// Fetches /api/auth/session via JS fetch from the current page context.
    /// Verify a matching result before completion; otherwise retain the browser.
    private func tryFetchSession(webView: WKWebView) {
        guard !hasCompleted, !isFetchingSession else { return }
        guard webView.url?.host?.contains("chatgpt.com") == true else { return }
        isFetchingSession = true
        logger.info("[CodexLogin] tryFetchSession from \(webView.url?.path ?? "?")")

        CodexAuthCoordinator.fetchSessionInPage(webView: webView, includeCookies: preserveExistingSession) { [weak self] session in
            Task { @MainActor [weak self] in
                guard let self, !self.hasCompleted else { return }
                defer { self.isFetchingSession = false }
                guard let session else {
                    self.logger.info("[CodexLogin] session fetch: no accessToken yet")
                    return
                }

                switch self.completionGate.evaluate(session, expectedAccountID: self.expectedAccountID) {
                case .complete:
                    do {
                        let count = session.cookiesToCommit?.count ?? 0
                        let recognized = !session.sessionToken.isEmpty
                        self.logger.notice("[CodexLogin] candidate workspace accepted cookieCount=\(count, privacy: .public) recognizedSessionCookie=\(recognized, privacy: .public)")
                        self.window?.title = "Checking ChatGPT sign-in…"
                        let verified = session.cookiesToCommit == nil ? session : try await self.stagedSessionVerifier(session)
                        guard !self.hasCompleted else { return }
                        guard CodexAuthCoordinator.acceptsInteractiveSession(verified, expectedAccountID: self.expectedAccountID) else {
                            self.window?.title = "Choose the saved ChatGPT account"
                            self.logger.notice("[CodexLogin] snapshot verification rejected workspace")
                            return
                        }
                        self.logger.notice("[CodexLogin] session verified; completing sign-in")
                        self.complete(CodexLoginResult(verified))
                    } catch {
                        guard !self.hasCompleted else { return }
                        self.window?.title = "Couldn't verify sign-in — click Check sign-in to retry"
                        if case NetworkError.httpError(let status) = error {
                            self.logger.notice("[CodexLogin] snapshot verification failed reason=http status=\(status, privacy: .public); existing session preserved")
                        } else if case NetworkError.accountIdentityMismatch = error {
                            self.logger.notice("[CodexLogin] snapshot verification failed reason=identity; existing session preserved")
                        } else {
                            self.logger.notice("[CodexLogin] snapshot verification failed reason=unavailable; existing session preserved")
                        }
                    }
                case .waitForAccount:
                    self.window?.title = "Choose the saved ChatGPT account"
                    self.logger.notice("[CodexLogin] waiting for the saved workspace")
                case .invalidSnapshot:
                    self.window?.title = "Couldn't read sign-in — click Check sign-in to retry"
                    self.logger.notice("[CodexLogin] snapshot token mismatch; existing session preserved")
                }
            }
        }
    }

    private func showLoginWindow() {
        guard let webView, window == nil else { return }
        let win = NSWindow(contentRect: .init(x: 0, y: 0, width: 520, height: 680),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Sign in to ChatGPT"
        let content = NSView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        let check = NSButton(title: "Check sign-in", target: self, action: #selector(checkSignIn))
        check.toolTip = "Finish connecting after signing in, without starting another login."
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelSignIn))
        for view in [webView, check, cancel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: content.topAnchor),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: check.topAnchor, constant: -12),
            check.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            check.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            cancel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            cancel.centerYAnchor.constraint(equalTo: check.centerYAnchor)
        ])
        win.contentView = content
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.delegate = self
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkSignIn() {
        guard let webView else { return }
        tryFetchSession(webView: webView)
    }

    @objc private func cancelSignIn() { fail(with: CancellationError()) }

    private func complete(_ result: CodexLoginResult) {
        guard !hasCompleted else { return }
        hasCompleted = true
        closePopupWindows()
        window?.close()
        window = nil; webView = nil; cookieObserver = nil
        let callback = onComplete
        selfRetain = nil
        callback(.success(result))
    }

    private func fail(with error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        closePopupWindows()
        window?.close()
        window = nil; webView = nil; cookieObserver = nil
        let callback = onComplete
        selfRetain = nil
        callback(.failure(error))
    }

    fileprivate func closePopupWindows() {
        for win in popupWindows { win.close() }
        popupWindows.removeAll()
    }

    fileprivate func hostPopup(_ popup: WKWebView, title: String) {
        let win = NSWindow(contentRect: popup.frame,
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = title
        win.contentView = popup
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.center()
        win.makeKeyAndOrderFront(nil)
        popupWindows.append(win)
    }

    fileprivate func closePopupWindow(hosting webView: WKWebView) {
        popupWindows.removeAll { win in
            guard win.contentView === webView else { return false }
            win.close()
            return true
        }
    }

}

@MainActor
extension CodexLoginWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.host?.contains("chatgpt.com") == true else { return }
        logger.info("[CodexLogin] didFinish: \(url.path)")

        if url.path.hasPrefix("/auth/") || url.path == "/login" {
            // Login page — window is already visible, nothing extra needed.
        } else {
            // Authenticated chatgpt.com page — try to fetch the session.
            tryFetchSession(webView: webView)
        }
    }
}

@MainActor
extension CodexLoginWindowController: WKUIDelegate {
    // Third-party sign-in providers (Google, Apple) run their OAuth flows in
    // window.open() popups. Without hosting the popup the flow dies silently.
    // The popup shares the login webview's WKWebsiteDataStore, so resulting
    // session cookies reach the existing cookie observer.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: .init(x: 0, y: 0, width: 480, height: 640), configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        hostPopup(popup, title: "Sign in")
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        closePopupWindow(hosting: webView)
    }
}

@MainActor
extension CodexLoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Only the main login window cancels the flow; popup windows close
        // as part of the OAuth handshake and must not abort it.
        guard (notification.object as? NSWindow) === window else { return }
        guard !hasCompleted else { return }
        fail(with: CancellationError())
    }
}

/// Fires when any cookie changes in the WK store, triggering a session fetch attempt.
private final class CodexCookieObserver: NSObject, WKHTTPCookieStoreObserver, @unchecked Sendable {
    private let onCookiesChanged: @MainActor @Sendable () -> Void
    init(onCookiesChanged: @MainActor @Sendable @escaping () -> Void) { self.onCookiesChanged = onCookiesChanged }

    func cookiesDidChange(in store: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in self?.onCookiesChanged() }
    }
}
