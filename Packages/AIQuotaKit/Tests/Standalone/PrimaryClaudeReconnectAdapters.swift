// Verbatim primary sign-in handler with the actual injected Claude coordinator.
// No real app model, registry, credential stores or login window is constructed.
import Foundation
@testable import AIQuotaKit
@MainActor final class PrimaryClaudeReconnectAdapter {
    struct Account { var workspaceID: String? }
    let claudeCoordinator: ClaudeAuthCoordinator
    var account: Account?
    var claudeError: NetworkError? = .tokenExpired
    var claudeState: AuthState = .authenticated
    var claudeRecoveryExhausted = false
    var enrolledServices: Set<ServiceType> = [.claude]
    var refreshTask: Task<Void, Never>?
    var refreshCount = 0
    init(_ coordinator: ClaudeAuthCoordinator, expected: String?) {
        claudeCoordinator = coordinator; account = expected.map { Account(workspaceID: $0) }
    }
    func primaryAccount(for: ServiceType) -> Account? { account }
    func trackServiceConnected(_ provider: ServiceType) {}
    func refreshClaude() async { refreshCount += 1 }
    func startAutoRefresh() {}
    // SOURCE_PRIMARY_SIGNIN
}
@MainActor func runPrimaryReconnectChecks() async throws {
    let a = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"
    let b = "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"
    for initial in [a, nil] as [String?] {
        for scenario in ["matching", "mismatch", "cancel"] {
            let memory = Memory(DummyAuth())
            let prompts = Memory(0)
            let auth = coordinator(memory, org: initial) {
                prompts.edit { $0 += 1 }
                if scenario == "cancel" { throw CancellationError() }
                return (scenario == "matching" ? a : b, [])
            }
            await auth.bootstrap()
            let sut = PrimaryClaudeReconnectAdapter(auth, expected: a)
            await sut.signInClaude()
            let matching = scenario == "matching"
            try require(prompts.read() == 1, "primary reconnect did not reach its explicit web login route")
            try require(memory.read().context?.orgId == (matching ? a : initial), "primary reconnect changed another organization's identity")
            try require(sut.refreshCount == (matching ? 1 : 0), "only verified reconnect can refresh")
            try require(await auth.state == (matching || initial != nil ? .authenticated : .unauthenticated), "cancel/mismatch changed coordinator state")
            if scenario == "cancel" {
                try require(sut.claudeError?.needsReconnect == true, "cancel lost the previous recovery action")
            }
        }
    }
    // A first connection still uses ordinary sign-in, without an expected saved organization.
    let firstMemory = Memory(DummyAuth())
    let firstAuth = coordinator(firstMemory) { (a, []) }
    await firstAuth.bootstrap()
    let first = PrimaryClaudeReconnectAdapter(firstAuth, expected: nil)
    await first.signInClaude()
    try require(firstMemory.read().context?.orgId == a && first.refreshCount == 1, "first connection regressed")
    print("PASS: 7 primary Claude web-reconnect checks: authenticated/disconnected × match/mismatch/cancel, memory-only coordinator")
}
