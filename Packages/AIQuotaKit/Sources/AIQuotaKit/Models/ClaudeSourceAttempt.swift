import Foundation

public struct ClaudeSourceAttempt: Codable, Sendable, Equatable {
    public enum ErrorCategory: String, Codable, Sendable, Equatable {
        case success
        case missingCredentials
        case expiredCredentials
        case missingScope
        case malformedCredentials
        case authFailed
        case policyBlocked
        case rateLimited
        case serverError
        case network
        case invalidResponse
    }

    public let source: ClaudeUsage.Source
    public let httpStatus: Int?
    public let errorCategory: ErrorCategory
    public let timestamp: Date

    public init(
        source: ClaudeUsage.Source,
        httpStatus: Int?,
        errorCategory: ErrorCategory,
        timestamp: Date = .now
    ) {
        self.source = source
        self.httpStatus = httpStatus
        self.errorCategory = errorCategory
        self.timestamp = timestamp
    }
}
