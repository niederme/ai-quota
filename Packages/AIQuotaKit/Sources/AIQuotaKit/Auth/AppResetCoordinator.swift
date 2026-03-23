import Foundation
import os

/// Orchestrates a full reset across both service coordinators.
/// Auth reset must complete before product state is cleared.
public actor AppResetCoordinator {

    private let claude: ClaudeAuthCoordinator
    private let codex: CodexAuthCoordinator
    private let logger = Logger(subsystem: "ai.quota", category: "reset")

    public struct ResetResult: Sendable {
        /// Any warnings from teardown (e.g. WebKit verification timeout).
        public let warnings: [String]
    }

    public init(claude: ClaudeAuthCoordinator, codex: CodexAuthCoordinator) {
        self.claude = claude
        self.codex = codex
    }

    /// Resets both service coordinators to signedOutByUser.
    /// Caller must stop and await the refresh loop before calling this.
    /// Returns after both coordinators have reached a stable terminal state.
    public func reset() async -> ResetResult {
        logger.info("[AppReset] beginning cross-service reset")

        // Run both auth resets concurrently.
        async let claudeReset: Void = claude.reset()
        async let codexReset: Void = codex.reset()
        _ = await (claudeReset, codexReset)

        logger.info("[AppReset] both coordinators reached terminal state")

        // Verify both are in signedOutByUser.
        let claudeState = await claude.state
        let codexState  = await codex.state
        var warnings: [String] = []
        if claudeState != .signedOutByUser {
            warnings.append("Claude coordinator ended in unexpected state: \(claudeState)")
        }
        if codexState != .signedOutByUser {
            warnings.append("Codex coordinator ended in unexpected state: \(codexState)")
        }
        if !warnings.isEmpty { logger.warning("[AppReset] \(warnings.joined(separator: "; "))") }

        return ResetResult(warnings: warnings)
    }
}
