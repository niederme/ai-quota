import Foundation

/// Persists non-secret account metadata and the selected account per provider.
public enum AccountRegistry {
    private static let suite = "group.com.niederme.AIQuota"
    private static let accountsKey = "connectedAccounts.v1"
    private static let selectedAccountIDsKey = "selectedConnectedAccountIDs.v1"
    private static let accountOrderKey = "connectedAccountOrder.v1"
    private static let migratedProvidersKey = "connectedAccountLegacyMigration.v1"

    private static var defaults: UserDefaults {
        let suiteName = isRunningTests
            ? "\(suite).tests.\(ProcessInfo.processInfo.processIdentifier)"
            : suite
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static var isRunningTests: Bool {
        Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
    }

    public static func accounts() -> [ConnectedAccount] {
        guard let data = defaults.data(forKey: accountsKey),
              let accounts = try? decoder.decode([ConnectedAccount].self, from: data)
        else { return [] }
        return accounts.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.id < rhs.id }
            return lhs.createdAt < rhs.createdAt
        }
    }

    public static func accounts(for provider: ServiceType) -> [ConnectedAccount] {
        accounts().filter { $0.provider == provider }
    }

    /// Display order is independent of the selected menu-bar or widget account.
    public static func orderedAccounts() -> [ConnectedAccount] {
        let stored = accounts()
        let byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
        let saved = defaults.stringArray(forKey: accountOrderKey) ?? []
        let ordered = saved.compactMap { byID[$0] }
        let included = Set(ordered.map(\.id))
        return ordered + stored.filter { !included.contains($0.id) }
    }

    public static func setAccountOrder(_ ids: [String]) {
        let valid = Set(accounts().map(\.id))
        var seen = Set<String>()
        defaults.set(ids.filter { valid.contains($0) && seen.insert($0).inserted }, forKey: accountOrderKey)
    }

    public static func account(id: String) -> ConnectedAccount? {
        accounts().first { $0.id == id }
    }

    /// Creates a new account or updates the account with the same provider and
    /// workspace identity. Passing no workspace ID intentionally creates a new
    /// account because display labels are not stable identities.
    @discardableResult
    public static func upsert(
        provider: ServiceType,
        displayLabel: String,
        workspaceID: String? = nil,
        authSource: AccountAuthSource,
        connectionKind: AccountConnectionKind = .isolated
    ) -> ConnectedAccount {
        if let workspaceID,
           var existing = accounts().first(where: {
               $0.provider == provider && $0.workspaceID == workspaceID
           }) {
            existing.displayLabel = displayLabel
            existing.authSource = authSource
            existing.connectionKind = connectionKind
            existing.updatedAt = .now
            save(existing)
            return existing
        }

        let account = ConnectedAccount(
            provider: provider,
            displayLabel: displayLabel,
            workspaceID: workspaceID,
            authSource: authSource,
            connectionKind: connectionKind
        )
        save(account)
        return account
    }

    public static func save(_ account: ConnectedAccount) {
        guard UUID(uuidString: account.id) != nil else { return }
        var stored = accounts()
        if let index = stored.firstIndex(where: { $0.id == account.id }) {
            stored[index] = account
        } else {
            stored.append(account)
        }
        persist(stored)
    }

    /// Removes one account and only that account's scoped snapshots and shared
    /// credential context. Other accounts for the same provider are untouched.
    public static func remove(id: String) {
        guard let removed = account(id: id) else { return }
        persist(accounts().filter { $0.id != id })
        clearSelectionIfNeeded(accountID: id, provider: removed.provider)

        switch removed.provider {
        case .codex:
            SharedDefaults.clearUsage(forAccountID: id)
            SharedAuthContextStore.clearCodex(forAccountID: id)
        case .claude:
            SharedDefaults.clearClaudeUsage(forAccountID: id)
            SharedAuthContextStore.clearClaude(forAccountID: id)
        }
    }

    public static func selectedAccountID(for provider: ServiceType) -> String? {
        selectedAccountIDs()[provider.rawValue]
    }

    public static func selectedAccount(for provider: ServiceType) -> ConnectedAccount? {
        guard let id = selectedAccountID(for: provider),
              let account = account(id: id),
              account.provider == provider
        else { return nil }
        return account
    }

    public static func selectAccount(id: String?, for provider: ServiceType) {
        var selected = selectedAccountIDs()
        if let id,
           let account = account(id: id),
           account.provider == provider {
            selected[provider.rawValue] = id
        } else {
            selected.removeValue(forKey: provider.rawValue)
        }
        persistSelectedAccountIDs(selected)
    }

    /// Copies the original singleton cache and shared widget auth context into a
    /// stable UUID-backed personal account once per provider. Legacy keys remain
    /// intact so older callers continue to work during the transition.
    @discardableResult
    public static func migrateLegacyAccountsIfNeeded() -> [ConnectedAccount] {
        var migrated = Set(defaults.stringArray(forKey: migratedProvidersKey) ?? [])
        var results: [ConnectedAccount] = []

        if !migrated.contains(ServiceType.codex.rawValue) {
            let usage = SharedDefaults.loadCachedUsage()
            let context = SharedAuthContextStore.loadCodex()
            if usage != nil || context != nil {
                let account = upsertLegacyAccount(
                    provider: .codex,
                    workspaceID: context?.accountID,
                    authSource: context?.sessionToken.isEmpty == false ? .webSession : .oauth
                )
                if let usage { SharedDefaults.saveUsage(usage, forAccountID: account.id) }
                if let context { SharedAuthContextStore.saveCodex(context, forAccountID: account.id) }
                if selectedAccountID(for: .codex) == nil { selectAccount(id: account.id, for: .codex) }
                results.append(account)
            }
            if usage != nil || context != nil {
                migrated.insert(ServiceType.codex.rawValue)
            }
        }

        if !migrated.contains(ServiceType.claude.rawValue) {
            let usage = SharedDefaults.loadCachedClaudeUsage()
            let context = SharedAuthContextStore.loadClaude()
            if usage != nil || context != nil {
                let account = upsertLegacyAccount(
                    provider: .claude,
                    workspaceID: context?.orgId,
                    authSource: context == nil ? .oauth : .webSession
                )
                if let usage { SharedDefaults.saveClaudeUsage(usage, forAccountID: account.id) }
                if let context { SharedAuthContextStore.saveClaude(context, forAccountID: account.id) }
                if selectedAccountID(for: .claude) == nil { selectAccount(id: account.id, for: .claude) }
                results.append(account)
            }
            if usage != nil || context != nil {
                migrated.insert(ServiceType.claude.rawValue)
            }
        }

        defaults.set(Array(migrated).sorted(), forKey: migratedProvidersKey)
        defaults.synchronize()
        return results
    }

    private static func upsertLegacyAccount(
        provider: ServiceType,
        workspaceID: String?,
        authSource: AccountAuthSource
    ) -> ConnectedAccount {
        if var existing = accounts().first(where: {
            $0.provider == provider && $0.connectionKind == .legacyPrimary
        }) {
            existing.workspaceID = workspaceID ?? existing.workspaceID
            existing.authSource = authSource
            existing.updatedAt = .now
            save(existing)
            return existing
        }

        return upsert(
            provider: provider,
            displayLabel: "Personal",
            workspaceID: workspaceID,
            authSource: authSource,
            connectionKind: .legacyPrimary
        )
    }

    private static func persist(_ accounts: [ConnectedAccount]) {
        guard let data = try? encoder.encode(accounts) else { return }
        defaults.set(data, forKey: accountsKey)
        defaults.synchronize()
    }

    private static func selectedAccountIDs() -> [String: String] {
        guard let data = defaults.data(forKey: selectedAccountIDsKey),
              let selected = try? decoder.decode([String: String].self, from: data)
        else { return [:] }
        return selected
    }

    private static func persistSelectedAccountIDs(_ selected: [String: String]) {
        guard let data = try? encoder.encode(selected) else { return }
        defaults.set(data, forKey: selectedAccountIDsKey)
        defaults.synchronize()
    }

    private static func clearSelectionIfNeeded(accountID: String, provider: ServiceType) {
        guard selectedAccountID(for: provider) == accountID else { return }
        selectAccount(id: nil, for: provider)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

#if DEBUG
    static func resetForTesting() {
        defaults.removeObject(forKey: accountsKey)
        defaults.removeObject(forKey: selectedAccountIDsKey)
        defaults.removeObject(forKey: accountOrderKey)
        defaults.removeObject(forKey: migratedProvidersKey)
        defaults.synchronize()
    }
#endif
}
