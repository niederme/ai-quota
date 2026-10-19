import Foundation
import MobileAccessCore

public struct DevinSourceAttempt: Codable, Sendable, Equatable {
    public enum ErrorCategory: String, Codable, Sendable, Equatable {
        case success
        case missingCredentials
        case authFailed
        case rateLimited
        case serverError
        case network
        case invalidResponse
    }

    public let source: DevinUsage.Source
    public let httpStatus: Int?
    public let errorCategory: ErrorCategory
    public let timestamp: Date

    public init(
        source: DevinUsage.Source,
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
