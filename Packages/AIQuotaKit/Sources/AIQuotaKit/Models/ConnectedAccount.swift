import Foundation

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
    public var workspaceID: String?
    public var authSource: AccountAuthSource
    public var connectionKind: AccountConnectionKind
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        provider: ServiceType,
        displayLabel: String,
        workspaceID: String? = nil,
        authSource: AccountAuthSource,
        connectionKind: AccountConnectionKind = .isolated,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id.uuidString
        self.provider = provider
        self.displayLabel = displayLabel
        self.workspaceID = workspaceID
        self.authSource = authSource
        self.connectionKind = connectionKind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
