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
        case .notAuthenticated: "Not signed in."
        case .tokenExpired: "Session expired. Please sign in again."
        case .refreshFailed: "Could not refresh session. Please sign in again."
        case .httpError(let code): (400...499).contains(code)
            ? "The service didn’t recognize this account (error \(code)). Try reconnecting."
            : "The service had a problem (error \(code)). AIQuota will try again."
        case .rateLimited: "Rate limited — try again in a moment."
        case .decodingError: "Unexpected response format from server."
        case .networkUnavailable: "No network connection."
        case .requestFailed: "Couldn’t update allowance. Try again."
        case .unknownEndpoint: "API endpoint not configured."
        case .accountIdentityMismatch: "Could not verify this session for the saved account. Its connection has been preserved."
        }
    }
}
