import Foundation
import MobileAccessCore
import OSLog

// MARK: - Request context

/// Value type the coordinator produces for authenticated requests.
public struct DevinRequestContext: Sendable {
    public let apiKey: String
    public let apiServerURL: URL
    public let source: DevinUsage.Source
}

// MARK: - DevinAuthCoordinator

/// Owns Devin auth state. Unlike the Codex/Claude coordinators there is no
/// interactive login flow: "sign in" means resolving a session credential from
/// Devin-owned local state (CLI credentials.toml, then the Devin app's
/// state.vscdb) or a manually pasted token, then validating it against
/// GetUserStatus. Devin's files are only ever read, never written.
public actor DevinAuthCoordinator {

    private static let signedOutKey = "devin.signedOutByUser"

    public private(set) var state: AuthState = .unknown
    private var continuations: [UUID: AsyncStream<AuthState>.Continuation] = [:]
    private var credential: DevinCredential?

    private let logger = Logger(subsystem: "ai.quota", category: "devin-coord")
    private let session: URLSession

    /// Injected for tests; defaults read real local Devin state.
    public typealias CredentialResolver = @Sendable () -> [DevinCredential]
    public typealias CredentialValidator = @Sendable (DevinCredential) async -> Bool
    private let credentialResolver: CredentialResolver
    private let credentialValidator: CredentialValidator

    public init(
        credentialResolver: CredentialResolver? = nil,
        credentialValidator: CredentialValidator? = nil
    ) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
        self.credentialResolver = credentialResolver ?? { DevinCredentialsStore.candidates() }
        self.credentialValidator = credentialValidator ?? { credential in
            await Self.validate(credential: credential)
        }
    }

    // MARK: - State stream

    public nonisolated var stateStream: AsyncStream<AuthState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(continuation: continuation, id: id) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id: id) }
            }
        }
    }

    private func register(continuation: AsyncStream<AuthState>.Continuation, id: UUID) {
        continuations[id] = continuation
        continuation.yield(state)
    }

    private func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func transition(to newState: AuthState) {
        state = newState
        logger.info("[DevinCoord] → \(String(describing: newState), privacy: .public)")
        for c in continuations.values { c.yield(newState) }
    }

    // MARK: - Bootstrap

    /// Called once at process start. Safe to call multiple times.
    public func bootstrap() async {
        guard state == .unknown else { return }

        if UserDefaults.standard.bool(forKey: Self.signedOutKey) {
            transition(to: .signedOutByUser)
            return
        }

        transition(to: .restoringSession)
        if await resolveAndValidate() {
            transition(to: .authenticated)
        } else {
            transition(to: .unauthenticated)
        }
    }

    // MARK: - Sign in / out

    /// Rescans local Devin state and validates what it finds.
    /// Throws when no credential exists anywhere or all candidates fail validation.
    public func signIn() async throws {
        guard await resolveAndValidate() else {
            transition(to: .unauthenticated)
            throw NetworkError.notAuthenticated
        }
        UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
        transition(to: .authenticated)
    }

    /// Validates and stores a session token the user pasted manually.
    public func signIn(manualToken token: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NetworkError.notAuthenticated }
        let candidate = DevinCredential(
            apiKey: trimmed,
            apiServerURL: DevinAPI.defaultAPIServerURL,
            source: .manual
        )
        guard await credentialValidator(candidate) else {
            throw NetworkError.notAuthenticated
        }
        DevinCredentialsStore.saveManualToken(trimmed)
        credential = candidate
        persistSharedAuthContext()
        UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
        transition(to: .authenticated)
    }

    public func signOut() async throws {
        credential = nil
        DevinCredentialsStore.clearManualToken()
        SharedAuthContextStore.clearDevin()
        UserDefaults.standard.set(true, forKey: Self.signedOutKey)
        transition(to: .signedOutByUser)
    }

    /// ResetCoordinator path — equivalent to signOut for Devin.
    public func reset() async {
        credential = nil
        DevinCredentialsStore.clearManualToken()
        SharedAuthContextStore.clearDevin()
        UserDefaults.standard.set(true, forKey: Self.signedOutKey)
        transition(to: .signedOutByUser)
    }

    // MARK: - Requests

    /// Throws `NetworkError.notAuthenticated` when no validated credential is held.
    public func requestContext() throws -> DevinRequestContext {
        guard let credential else { throw NetworkError.notAuthenticated }
        return DevinRequestContext(
            apiKey: credential.apiKey,
            apiServerURL: credential.apiServerURL,
            source: credential.source
        )
    }

    /// Called after a usage fetch fails with an auth error. Re-resolves local
    /// credentials (the user may have run `devin auth login` again or the Devin
    /// app may have rotated its token) and validates. True when a working
    /// credential was found.
    public func revalidateSessionAfterAuthFailure() async -> Bool {
        if await resolveAndValidate() {
            transition(to: .authenticated)
            return true
        }
        transition(to: .unauthenticated)
        return false
    }

    /// Enrolled-session recovery at launch / popover open. No prompts exist for
    /// Devin — recovery is just a rescan + validate.
    public func restoreWithoutPromptIfPossible(allowSignedOutByUser: Bool) async -> Bool {
        if !allowSignedOutByUser,
           UserDefaults.standard.bool(forKey: Self.signedOutKey) {
            return false
        }
        if await resolveAndValidate() {
            transition(to: .authenticated)
            return true
        }
        return false
    }

    public func hasUsableCredentials() async -> Bool {
        await resolveAndValidate()
    }

    // MARK: - Private

    /// Discovers candidate credentials and keeps the first the server accepts.
    /// The winning credential is held for `requestContext()` and mirrored into
    /// the shared auth context for the widget extension.
    private func resolveAndValidate() async -> Bool {
        for candidate in credentialResolver() where await credentialValidator(candidate) {
            credential = candidate
            persistSharedAuthContext()
            return true
        }
        credential = nil
        SharedAuthContextStore.clearDevin()
        return false
    }

    private func persistSharedAuthContext() {
        guard let credential else { return }
        SharedAuthContextStore.saveDevin(SharedDevinAuthContext(
            apiKey: credential.apiKey,
            apiServerURL: credential.apiServerURL.absoluteString
        ))
    }

    /// A cheap probe: status 2xx means the credential is accepted.
    /// Never logs the key or response body.
    private static func validate(credential: DevinCredential) async -> Bool {
        let request = DevinAPI.userStatusRequest(
            apiServerURL: credential.apiServerURL,
            apiKey: credential.apiKey
        )
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        do {
            let (_, response) = try await URLSession(configuration: config).data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
