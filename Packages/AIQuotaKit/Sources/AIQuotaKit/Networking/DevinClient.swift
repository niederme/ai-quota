import Foundation
import MobileAccessCore
import OSLog

/// Fetches Devin quota via the seat-management GetUserStatus call using the
/// credential the coordinator resolved from local Devin state.
public actor DevinClient {
    private let logger = Logger(subsystem: "app.aiquota", category: "DevinClient")
    private let coordinator: DevinAuthCoordinator
    private let session: URLSession

    public init(coordinator: DevinAuthCoordinator) {
        self.coordinator = coordinator
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)
    }

    public func fetchUsage(now: Date = .now) async throws -> DevinUsage {
        let context = try await coordinator.requestContext()
        var request = DevinAPI.userStatusRequest(
            apiServerURL: context.apiServerURL,
            apiKey: context.apiKey
        )
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            recordAttempt(source: context.source, httpStatus: nil, category: .network)
            throw NetworkError.networkUnavailable
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            recordAttempt(source: context.source, httpStatus: http.statusCode, category: .authFailed)
            throw NetworkError.notAuthenticated
        case 429:
            recordAttempt(source: context.source, httpStatus: 429, category: .rateLimited)
            throw NetworkError.rateLimited
        default:
            recordAttempt(source: context.source, httpStatus: http.statusCode, category: .serverError)
            throw NetworkError.httpError(statusCode: http.statusCode)
        }

        do {
            let usage = try DevinAPI.decodeUserStatus(data, now: now, source: context.source)
            recordAttempt(source: context.source, httpStatus: http.statusCode, category: .success)
            return usage
        } catch {
            recordAttempt(source: context.source, httpStatus: http.statusCode, category: .invalidResponse)
            throw NetworkError.decodingError(underlying: error)
        }
    }

    private func recordAttempt(
        source: DevinUsage.Source,
        httpStatus: Int?,
        category: DevinSourceAttempt.ErrorCategory
    ) {
        SharedDefaults.appendDevinSourceAttempt(
            DevinSourceAttempt(source: source, httpStatus: httpStatus, errorCategory: category)
        )
    }
}
