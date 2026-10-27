import Foundation
import Testing
@testable import AIQuotaKit

@Suite(.serialized)
struct AccountRegistryTests {
    @Test("Mac overview stacks every account and scrolls only on real height overflow")
    func gridGeometry() {
        for width in [280.0, 420.0, 480.0] {
            for count in 1...6 {
                #expect(MacAccountGridLayout.columns(for: width) == 1)
                #expect(MacAccountGridLayout.rows(accountCount: count, width: width) == count)
                #expect(MacAccountGridLayout.viewportHeight(accountCount: count, width: width,
                                                             availableHeight: 1200) == Double(count) * 156 + 24)
                #expect(MacAccountGridLayout.viewportHeight(accountCount: count, width: width,
                                                             availableHeight: 300) <= 300)
            }
        }
        #expect(MacAccountGridLayout.viewportHeight(accountCount: 0, width: 480,
                                                     availableHeight: 1200) == 336)
        #expect(MacAccountGridLayout.viewportHeight(accountCount: 6, width: 480,
                                                     availableHeight: 1200) == 960)
        #expect(MacAccountGridLayout.viewportHeight(accountCount: 6, width: 480,
                                                     availableHeight: 300) == 300)
    }

    @Test("Mac account overview never borrows another account's metric")
    func overviewUsageIsAccountScoped() {
        let codex = ConnectedAccount(provider: .codex, displayLabel: "Personal",
                                     authSource: .oauth, connectionKind: .legacyPrimary)
        let claude = ConnectedAccount(provider: .claude, displayLabel: "Work",
                                      authSource: .webSession, connectionKind: .legacyPrimary)
        let isolated = ConnectedAccount(provider: .codex, displayLabel: "Other",
                                        authSource: .oauth)
        #expect(MacAccountOverviewUsage.claude(account: codex, isolated: nil,
                                                primary: .placeholder) == nil)
        #expect(MacAccountOverviewUsage.codex(account: claude, isolated: nil,
                                               primary: .placeholder) == nil)
        #expect(MacAccountOverviewUsage.codex(account: isolated, isolated: nil,
                                               primary: .placeholder) == nil)
        #expect(MacAccountOverviewUsage.codex(account: codex, isolated: nil,
                                               primary: .placeholder) != nil)
    }

    @Test("menu-bar choices preserve explicit empty and more-than-two selections")
    func menuBarSelectionPersists() throws {
        var settings = AppSettings.default
        #expect(settings.menuBarAccountIDs == nil)
        settings.menuBarAccountIDs = []
        let empty = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(empty.menuBarAccountIDs == [])

        let ids = (0..<6).map { _ in UUID().uuidString }
        settings.menuBarAccountIDs = ids
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.menuBarAccountIDs == ids)
    }

    @Test("account order persists independently of provider selection")
    func orderIsIndependent() {
        AccountRegistry.resetForTesting()
        defer { AccountRegistry.resetForTesting() }
        let first = AccountRegistry.upsert(provider: .codex, displayLabel: "Personal", authSource: .oauth)
        let second = AccountRegistry.upsert(provider: .claude, displayLabel: "Work", authSource: .webSession)
        let third = AccountRegistry.upsert(provider: .codex, displayLabel: "Other", authSource: .oauth)
        AccountRegistry.selectAccount(id: first.id, for: .codex)
        AccountRegistry.setAccountOrder([second.id, first.id, third.id])
        #expect(AccountRegistry.orderedAccounts().map(\.id) == [second.id, first.id, third.id])
        #expect(AccountRegistry.selectedAccountID(for: .codex) == first.id)
    }

    @Test("menu-bar gauges follow saved account order without changing visibility")
    func menuBarFollowsAccountOrder() {
        AccountRegistry.resetForTesting()
        defer { AccountRegistry.resetForTesting() }
        let personal = AccountRegistry.upsert(provider: .codex, displayLabel: "Personal", authSource: .oauth)
        let hidden = AccountRegistry.upsert(provider: .claude, displayLabel: "Hidden", authSource: .webSession)
        let work = AccountRegistry.upsert(provider: .codex, displayLabel: "Work", authSource: .oauth)
        var settings = AppSettings.default
        settings.menuBarAccountIDs = [personal.id, work.id]

        AccountRegistry.setAccountOrder([work.id, hidden.id, personal.id])
        #expect(settings.menuBarAccounts(in: AccountRegistry.orderedAccounts())?.map(\.id) == [work.id, personal.id])
        AccountRegistry.setAccountOrder([personal.id, hidden.id, work.id])
        #expect(settings.menuBarAccounts(in: AccountRegistry.orderedAccounts())?.map(\.id) == [personal.id, work.id])
        #expect(settings.menuBarAccountIDs == [personal.id, work.id])

        // Re-enabling a gauge must put it back in account-list order, not at the end.
        settings.menuBarAccountIDs = [work.id, personal.id]
        #expect(settings.menuBarAccounts(in: AccountRegistry.orderedAccounts())?.map(\.id) == [personal.id, work.id])
    }

    @Test("menu-bar ordering preserves legacy and empty choices and ignores stale IDs")
    func menuBarOrderingEdgeCases() {
        let account = ConnectedAccount(provider: .claude, displayLabel: "Work", authSource: .webSession)
        var settings = AppSettings.default
        #expect(settings.menuBarAccounts(in: [account]) == nil)
        settings.menuBarAccountIDs = []
        #expect(settings.menuBarAccounts(in: [account]) == [])
        settings.menuBarAccountIDs = ["removed-account", account.id, account.id]
        #expect(settings.menuBarAccounts(in: [account])?.map(\.id) == [account.id])
    }

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

@Suite("New account menu bar defaults")
struct NewAccountMenuBarDefaultsTests {
    @Test("The first two accounts are visible and later accounts require opting in")
    func defaultVisibility() {
        var settings = AppSettings.default
        settings.registerMenuBarAccount(id: "personal", existingAccountIDs: [])
        settings.registerMenuBarAccount(id: "work", existingAccountIDs: ["personal"])
        settings.registerMenuBarAccount(id: "third", existingAccountIDs: ["personal", "work"])
        #expect(settings.menuBarAccountIDs == ["personal", "work"])
        settings.registerMenuBarAccount(id: "fourth", existingAccountIDs: ["personal", "work", "third"], showInMenuBar: true)
        #expect(settings.menuBarAccountIDs == ["personal", "work", "fourth"])
    }

    @Test("Hidden accounts still count toward the first two")
    func hiddenAccountsCount() {
        var settings = AppSettings.default
        settings.menuBarAccountIDs = []
        settings.registerMenuBarAccount(id: "third", existingAccountIDs: ["personal", "work"], showInMenuBar: false)
        #expect(settings.menuBarAccountIDs == [])
    }

    @Test("Adding a second account preserves the first account's explicit opt-out")
    func preservesOtherChoices() {
        var settings = AppSettings.default
        settings.menuBarAccountIDs = []
        settings.registerMenuBarAccount(id: "work", existingAccountIDs: ["personal"])
        #expect(settings.menuBarAccountIDs == ["work"])
    }

    @Test("Reconnecting or replaying setup cannot restore a hidden gauge")
    func doesNotReapplyDefaults() {
        var settings = AppSettings.default
        settings.menuBarAccountIDs = []
        settings.registerMenuBarAccount(id: "personal", existingAccountIDs: ["personal"])
        #expect(settings.menuBarAccountIDs == [])
    }

    @Test("Account visibility survives a save and reload")
    func roundTrip() throws {
        var settings = AppSettings.default
        settings.registerMenuBarAccount(id: "personal", existingAccountIDs: [])
        settings.registerMenuBarAccount(id: "third", existingAccountIDs: ["personal", "work"], showInMenuBar: true)
        let reloaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(reloaded.menuBarAccountIDs == ["personal", "third"])
    }
}
