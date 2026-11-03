import Foundation

/// A coordinator's cached authenticated state does not override a rejected
/// allowance request. Keep recovery based on typed errors, never message text.
public enum AccountRecoveryAction: Equatable, Sendable {
    case none
    case retry
    case reconnect

    public static func resolve(authenticated: Bool, error: NetworkError?, hasIssue: Bool = false) -> Self {
        if !authenticated || error?.needsReconnect == true { return .reconnect }
        return error != nil || hasIssue ? .retry : .none
    }
}
