// Executes the exact additional-card signIn body with the real, fully injected
// Claude coordinator. Registry binding and subsequent refresh are memory adapters.
import Foundation
@testable import AIQuotaKit

@MainActor final class AdditionalClaudeAdapter {
    struct Account { var workspaceID: String? }
    let provider: ServiceType = .claude
    var state: AuthState = .unauthenticated
    var issue: String? = "previous issue"
    var account: Account
    var refreshCount = 0
    var isAuthenticated: Bool { state == .authenticated }
    let codexCoordinator: CodexAuthCoordinator? = nil
    let claudeCoordinator: ClaudeAuthCoordinator?
    init(_ coordinator: ClaudeAuthCoordinator, expected: String) {
        claudeCoordinator = coordinator
        account = Account(workspaceID: expected)
    }
    func adoptState(_ state: AuthState) { self.state = state }
    func bootstrap() async { await claudeCoordinator?.bootstrap() }
    func signOut() async { state = .unauthenticated }
    func refresh() async { refreshCount += 1 }
    func bindIdentity() async -> Bool {
        guard let context = try? await claudeCoordinator?.requestContext(),
              context.orgId == account.workspaceID else { issue = "mismatch"; return false }
        return true
    }
    // SOURCE_ADDITIONAL_SIGNIN
}

@MainActor func runAdditionalReconnectChecks() async throws {
    let a = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"
    let b = "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"
    var failures: [String] = []
    for scenario in ["mismatch", "matching", "cancel"] {
        let memory = Memory(DummyAuth())
        let auth = coordinator(memory) {
            if scenario == "cancel" { throw CancellationError() }
            return (scenario == "matching" ? a : b, [])
        }
        await auth.bootstrap()
        let card = AdditionalClaudeAdapter(auth, expected: a)
        await card.signIn()
        let matching = scenario == "matching"
        if memory.read().context?.orgId != (matching ? a : nil)
            || card.isAuthenticated != matching || card.refreshCount != (matching ? 1 : 0) {
            failures.append(scenario)
            print("FAIL: additional Claude card \(scenario)")
        } else { print("PASS: additional Claude card \(scenario)") }
    }
    try require(failures.isEmpty, "additional reconnect source regression failures: \(failures.joined(separator: ", "))")
    print("PASS: 3 additional-card source-body checks with injected coordinator")
}
