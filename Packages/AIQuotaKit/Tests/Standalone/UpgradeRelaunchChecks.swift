// Memory-only diagnostic evidence for the shipped coordinator code. This is a
// process-reconstruction simulation, not a TestFlight installation or live login.
import Foundation
@testable import AIQuotaKit
final class Box<T>: @unchecked Sendable {
    let lock = NSLock(); var value: T
    init(_ value: T) { self.value = value }
    func read() -> T { lock.withLock { value } }
    func set(_ value: T) { lock.withLock { self.value = value } }
}
func check(_ condition: Bool, _ label: String) throws {
    guard condition else { throw NSError(domain: label, code: 1) }
}
@main enum Checks {
    static func main() async throws {
        var checks = 0
        let promptCount = Box(0)
        for provider in [ServiceType.codex, .claude] {
            for index in 1...2 {
                let storage = UUID()
                let scope = "synthetic-scope-\(provider)-\(index)"
                let before = ConnectedAccount(id: storage, provider: provider, displayLabel: "Account \(index)", workspaceID: scope,
                                              authSource: .webSession, connectionKind: .isolated, labelExplicitlyNamed: false)
                var renamed = before; renamed.displayLabel = provider == .codex ? "Codex Business" : "Claude Enterprise"
                let after = try JSONDecoder().decode(ConnectedAccount.self, from: JSONEncoder().encode(renamed))
                try check(before.id == after.id && before.workspaceID == after.workspaceID && before.connectionKind == after.connectionKind, "label upgrade retains storage/identity keys")
                if provider == .codex {
                    let memory = Box<SharedCodexAuthContext?>(nil)
                    func instance(_ available: Bool) -> CodexAuthCoordinator {
                        CodexAuthCoordinator(accountStorageID: storage, probe: { .notFound }, headlessSessionReviver: { nil },
                            tokenRefresher: { _ in throw NetworkError.refreshFailed },
                            oauthCredentialsLoader: {
                                guard available else { throw CodexOAuthCredentialsError.notFound }
                                return CodexOAuthCredentials(accessToken: "synthetic-only", refreshToken: "synthetic-only", idToken: "synthetic-only",
                                    accountID: scope, lastRefresh: .now, expiresAt: Date.now.addingTimeInterval(3600))
                            }, expectedAccountID: { scope }, contextWriter: { memory.set($0) },
                            interactiveSessionProvider: { _ in promptCount.set(promptCount.read() + 1); throw CancellationError() },
                            sessionCommitter: { _, _ in }, stagedSessionVerifier: { $0 }, sessionClearer: {})
                    }
                    for _ in 0..<2 {
                        let coordinator = instance(true); await coordinator.bootstrap()
                        try check(await coordinator.state == .authenticated, "Codex restores across relaunch")
                        try check(memory.read()?.accountID == scope, "Codex keeps selected scope")
                        checks += 1
                    }
                    let unavailable = instance(false); await unavailable.bootstrap()
                    try check(await unavailable.state == .unauthenticated && memory.read()?.accountID == scope, "unavailable Codex restore does not rewrite saved identity")
                } else {
                    let memory = Box<SharedClaudeAuthContext?>(nil)
                    func instance(_ available: Bool) -> ClaudeAuthCoordinator {
                        ClaudeAuthCoordinator(accountStorageID: storage, probe: { available ? .found(orgId: scope, cookies: []) : .notFound },
                            headlessSessionReviver: { .notFound }, oauthCredentialsLoader: { _ in throw ClaudeOAuthCredentialsError.notFound },
                            keychainAccessAllowed: { false }, sessionValidator: { _ in .invalid }, webSessionClearer: {}, webSessionRestorer: { _ in },
                            loginWindowRunner: { promptCount.set(promptCount.read() + 1); throw CancellationError() }, contextWriter: { memory.set($0) },
                            signedOutReader: { false }, signedOutWriter: { _ in }, webSessionResetter: {}, webSessionVerifier: { true })
                    }
                    for _ in 0..<2 {
                        let coordinator = instance(true); await coordinator.bootstrap()
                        try check(await coordinator.state == .authenticated, "Claude restores across relaunch")
                        try check(memory.read()?.orgId == scope, "Claude keeps selected scope")
                        checks += 1
                    }
                    let unavailable = instance(false); await unavailable.bootstrap()
                    try check(await unavailable.state == .unauthenticated && memory.read()?.orgId == scope, "unavailable Claude restore does not rewrite saved identity")
                }
                checks += 2
            }
        }
        try check(promptCount.read() == 0, "launch/upgrade must not prompt sign-in")
        print("PASS: \(checks + 1) memory-only four-account relaunch/identity checks; no live secrets, stores or network. This does not reproduce an OS TestFlight upgrade.")
    }
}
