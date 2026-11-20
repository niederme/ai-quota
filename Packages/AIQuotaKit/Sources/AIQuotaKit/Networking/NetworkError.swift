import Foundation

public enum NetworkError: Error, Sendable, LocalizedError {
    case notAuthenticated
    case tokenExpired
    case refreshFailed
    case httpError(statusCode: Int)
    case rateLimited
    case decodingError(underlying: any Error)
    case networkUnavailable
    case requestFailed
    case unknownEndpoint
    case accountIdentityMismatch

    public var isAuthError: Bool {
        switch self {
        case .notAuthenticated, .tokenExpired, .refreshFailed: true
        default: false
        }
    }

    /// UI recovery is separate from automatic authentication-error retries.
    public var needsReconnect: Bool {
        if case .accountIdentityMismatch = self { return true }
        return isAuthError
    }

    /// A 4xx other than rate limiting means the saved account or organization
    /// was not found or not accepted. Retrying won't help; signing in again
    /// captures a fresh identity. UI-only: does not change automatic recovery.
    public var suggestsReconnect: Bool {
        if needsReconnect { return true }
        if case .httpError(let code) = self { return (400...499).contains(code) && code != 429 }
        return false
    }

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: String(localized: "Not signed in.", bundle: .module)
        case .tokenExpired: String(localized: "Session expired. Please sign in again.", bundle: .module)
        case .refreshFailed: String(localized: "Could not refresh session. Please sign in again.", bundle: .module)
        case .httpError(let code): (400...499).contains(code)
            ? String(localized: "The service didn’t recognize this account (error \(code)). Try reconnecting.", bundle: .module)
            : String(localized: "The service had a problem (error \(code)). AIQuota will try again.", bundle: .module)
        case .rateLimited: String(localized: "Rate limited — try again in a moment.", bundle: .module)
        case .decodingError: String(localized: "Unexpected response format from server.", bundle: .module)
        case .networkUnavailable: String(localized: "No network connection.", bundle: .module)
        case .requestFailed: String(localized: "Couldn’t update allowance. Try again.", bundle: .module)
        case .unknownEndpoint: String(localized: "API endpoint not configured.", bundle: .module)
        case .accountIdentityMismatch: String(localized: "That sign-in is for a different account than the one saved here, so nothing changed. Reconnect with the original account.", bundle: .module)
        }
    }
}
