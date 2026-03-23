import Foundation

// MARK: - AuthState

/// The complete set of states a service coordinator may occupy.
/// Any transition not listed in the legal transition table in
/// docs/auth-coordinator-spec.md is illegal and will be rejected.
public enum AuthState: Equatable, Sendable {
    /// Process has not yet completed bootstrap evaluation.
    /// Startup-only; never re-entered after bootstrap settles.
    case unknown

    /// Bootstrap probe is currently running.
    case restoringSession

    /// A coordinator transition confirmed a valid WebKit-backed session.
    case authenticated

    /// Probe or revalidation found no usable session; user may sign in.
    case unauthenticated

    /// Explicit user intent blocks silent re-auth until a new explicit sign-in.
    case signedOutByUser

    /// Interactive login flow is in progress.
    case signingIn

    /// Teardown is in progress following an explicit sign-out.
    case signingOut

    /// Teardown is in progress following a reset request.
    case resetting
}

// MARK: - AuthCoordinatorError

public enum AuthCoordinatorError: Error, Sendable {
    /// The method was called from a state that does not permit this transition.
    case invalidTransition(from: AuthState)
}
