import Foundation

public enum NetworkError: Error, Sendable, LocalizedError {
    case notAuthenticated
    case tokenExpired
    case refreshFailed
    case httpError(statusCode: Int)
    case rateLimited
    case decodingError(underlying: any Error)
    case networkUnavailable
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

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Not signed in."
        case .tokenExpired: "Session expired. Please sign in again."
        case .refreshFailed: "Could not refresh session. Please sign in again."
        case .httpError(let code): "Server returned error \(code)."
        case .rateLimited: "Rate limited — try again in a moment."
        case .decodingError: "Unexpected response format from server."
        case .networkUnavailable: "No network connection."
        case .unknownEndpoint: "API endpoint not configured."
        case .accountIdentityMismatch: "Could not verify this session for the saved account. Its connection has been preserved."
        }
    }
}
