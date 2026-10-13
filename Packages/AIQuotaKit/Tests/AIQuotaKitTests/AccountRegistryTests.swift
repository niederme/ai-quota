import Foundation
import Testing
@testable import AIQuotaKit

@Suite(.serialized)
struct AccountRegistryTests {
    @Test("upsert preserves UUID identity and selections are provider-scoped")
    func upsertAndSelection() {
        AccountRegistry.resetForTesting()
        defer { AccountRegistry.resetForTesting() }

        let workspaceID = UUID().uuidString
        let first = AccountRegistry.upsert(
            provider: .codex,
            displayLabel: "Work",
            workspaceID: workspaceID,
            authSource: .oauth
        )
        let updated = AccountRegistry.upsert(
            provider: .codex,
            displayLabel: "Work renamed",
            workspaceID: workspaceID,
            authSource: .webSession
        )
        let claude = AccountRegistry.upsert(
            provider: .claude,
            displayLabel: "Claude Work",
            workspaceID: UUID().uuidString,
            authSource: .oauth
        )

        AccountRegistry.selectAccount(id: first.id, for: .codex)
        AccountRegistry.selectAccount(id: claude.id, for: .claude)

        #expect(UUID(uuidString: first.id) != nil)
        #expect(updated.id == first.id)
        #expect(updated.displayLabel == "Work renamed")
        #expect(AccountRegistry.selectedAccountID(for: .codex) == first.id)
        #expect(AccountRegistry.selectedAccountID(for: .claude) == claude.id)
    }

    @Test("legacy singleton state migrates once into account-scoped storage")
    func migratesLegacyState() throws {
        AccountRegistry.resetForTesting()
        SharedDefaults.clearUsage()
        defer {
            for account in AccountRegistry.accounts() {
                SharedDefaults.clearUsage(forAccountID: account.id)
            }
            SharedDefaults.clearUsage()
            AccountRegistry.resetForTesting()
        }

        SharedDefaults.saveUsage(.placeholder)

        let migrated = AccountRegistry.migrateLegacyAccountsIfNeeded()
        let account = try #require(migrated.first { $0.provider == .codex })

        #expect(account.connectionKind == .legacyPrimary)
        #expect(UUID(uuidString: account.id) != nil)
        #expect(AccountRegistry.selectedAccountID(for: .codex) == account.id)
        #expect(SharedDefaults.loadCachedUsage(forAccountID: account.id) != nil)
        #expect(AccountRegistry.migrateLegacyAccountsIfNeeded().isEmpty)
    }
}
