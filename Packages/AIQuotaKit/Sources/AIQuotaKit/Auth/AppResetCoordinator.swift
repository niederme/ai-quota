import Foundation
import os

/// Orchestrates a full reset across all service coordinators.
/// Auth reset must complete before product state is cleared.
public actor AppResetCoordinator {

    private let claude: ClaudeAuthCoordinator
    private let codex: CodexAuthCoordinator
    private let devin: DevinAuthCoordinator
    private let logger = Logger(subsystem: "ai.quota", category: "reset")

    public struct ResetResult: Sendable {
        /// Any warnings from teardown (e.g. WebKit verification timeout).
        public let warnings: [String]
    }

    public init(claude: ClaudeAuthCoordinator, codex: CodexAuthCoordinator, devin: DevinAuthCoordinator) {
        self.claude = claude
        self.codex = codex
        self.devin = devin
    }

    /// Resets all service coordinators to signedOutByUser.
    /// Caller must stop and await the refresh loop before calling this.
    /// Returns after all coordinators have reached a stable terminal state.
    public func reset() async -> ResetResult {
        logger.info("[AppReset] beginning cross-service reset")

        async let claudeReset: Void = claude.reset()
        async let codexReset: Void = codex.reset()
        async let devinReset: Void = devin.reset()
        _ = await (claudeReset, codexReset, devinReset)

        logger.info("[AppReset] all coordinators reached terminal state")

        // Verify all are in signedOutByUser.
        let claudeState = await claude.state
        let codexState  = await codex.state
        let devinState  = await devin.state
        var warnings: [String] = []
        if claudeState != .signedOutByUser {
            warnings.append("Claude coordinator ended in unexpected state: \(claudeState)")
        }
        if codexState != .signedOutByUser {
            warnings.append("Codex coordinator ended in unexpected state: \(codexState)")
        }
        if devinState != .signedOutByUser {
            warnings.append("Devin coordinator ended in unexpected state: \(devinState)")
        }
        if !warnings.isEmpty { logger.warning("[AppReset] \(warnings.joined(separator: "; "))") }

        return ResetResult(warnings: warnings)
    }
}
