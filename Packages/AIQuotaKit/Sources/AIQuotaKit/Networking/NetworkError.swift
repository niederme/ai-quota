import Foundation

public enum NetworkError: Error, Sendable, LocalizedError {
    case notAuthenticated
    case tokenExpired
    case refreshFailed
    case httpError(statusCode: Int)
    case decodingError(underlying: any Error)
    case networkUnavailable
    case unknownEndpoint

    public var isAuthError: Bool {
        switch self {
        case .notAuthenticated, .tokenExpired, .refreshFailed: true
        default: false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Not signed in."
        case .tokenExpired: "Session expired. Please sign in again."
        case .refreshFailed: "Could not refresh session. Please sign in again."
        case .httpError(let code): "Server returned error \(code)."
        case .decodingError: "Unexpected response format from server."
        case .networkUnavailable: "No network connection."
        case .unknownEndpoint: "API endpoint not configured."
        }
    }
}
