import Foundation
import MobileAccessCore

public enum AccountAuthSource: String, Codable, CaseIterable, Sendable {
    case oauth
    case webSession
}

public enum AccountConnectionKind: String, Codable, CaseIterable, Sendable {
    /// The original per-provider coordinator and its shared WebKit data store.
    case legacyPrimary
    /// An account with its own account-scoped session and persistence.
    case isolated
}

/// Non-secret metadata for a connected provider account.
///
/// Credentials and cookies are deliberately stored separately in
/// `SharedAuthContextStore` so registry data is safe to inspect and diagnose.
public struct ConnectedAccount: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public var provider: ServiceType
    public var displayLabel: String
    /// Nil for older metadata; true after an explicit rename.
    public var labelExplicitlyNamed: Bool?
    public var workspaceID: String?
    public var authSource: AccountAuthSource
    public var connectionKind: AccountConnectionKind
    public let createdAt: Date
    public var updatedAt: Date

    public var cachedPlan: String? {
        if provider == .codex {
            if let usage = SharedDefaults.loadCachedUsage(forAccountID: id), workspaceID == nil || usage.accountID == workspaceID { return usage.displayPlan }
            if connectionKind == .legacyPrimary, let usage = SharedDefaults.loadCachedUsage(),
               let workspaceID, usage.accountID == workspaceID { return usage.displayPlan }
        } else {
            if let usage = SharedDefaults.loadCachedClaudeUsage(forAccountID: id), workspaceID == nil || usage.quotaScopeID == workspaceID { return usage.planDisplayName }
            if connectionKind == .legacyPrimary, let usage = SharedDefaults.loadCachedClaudeUsage(),
               let workspaceID, usage.quotaScopeID == workspaceID { return usage.planDisplayName }
        }
        return nil
    }
    public func identity(plan: String? = nil) -> AccountIdentity {
        .init(key: id, service: provider == .codex ? "Codex" : "Claude", label: displayLabel,
              plan: plan ?? cachedPlan, origin: labelExplicitlyNamed == true ? .user : labelExplicitlyNamed == false ? .generated : .unknown)
    }
    public func presentation(plan: String? = nil, among peers: [ConnectedAccount]? = nil) -> AccountPresentation {
        AccountPresentation.resolve(identity(plan: plan), among: (peers ?? AccountRegistry.accounts()).map { $0.identity() })
    }
    public var alertDisplayName: String { presentation().title }

    public init(
        id: UUID = UUID(),
        provider: ServiceType,
        displayLabel: String,
        workspaceID: String? = nil,
        authSource: AccountAuthSource,
        connectionKind: AccountConnectionKind = .isolated,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        labelExplicitlyNamed: Bool? = nil
    ) {
        self.id = id.uuidString
        self.provider = provider
        self.displayLabel = displayLabel
        self.labelExplicitlyNamed = labelExplicitlyNamed
        self.workspaceID = workspaceID
        self.authSource = authSource
        self.connectionKind = connectionKind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
