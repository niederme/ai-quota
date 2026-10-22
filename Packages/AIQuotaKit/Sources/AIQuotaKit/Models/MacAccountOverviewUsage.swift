/// Resolves one account's overview reading without falling through to the
/// other provider or borrowing the primary connection for an isolated account.
public enum MacAccountOverviewUsage {
    public static func codex(
        account: ConnectedAccount,
        isolated: CodexUsage?,
        primary: CodexUsage?
    ) -> CodexUsage? {
        guard account.provider == .codex else { return nil }
        return account.connectionKind == .legacyPrimary ? primary : isolated
    }

    public static func claude(
        account: ConnectedAccount,
        isolated: ClaudeUsage?,
        primary: ClaudeUsage?
    ) -> ClaudeUsage? {
        guard account.provider == .claude else { return nil }
        return account.connectionKind == .legacyPrimary ? primary : isolated
    }
}
