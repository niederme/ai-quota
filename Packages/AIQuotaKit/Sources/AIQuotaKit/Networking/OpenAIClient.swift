import Foundation
import OSLog

public actor OpenAIClient {
    private let logger = Logger(subsystem: "app.aiquota", category: "OpenAIClient")
    private let coordinator: CodexAuthCoordinator
    private let session: URLSession

    private let baseURL = URL(string: "https://chatgpt.com")!
    // Confirmed endpoint from network inspection of chatgpt.com/codex/settings/usage
    private let usagePath = "/backend-api/wham/usage"
    private let creditUsageEventsPath = "/backend-api/wham/usage/credit-usage-events"
    private let autoTopUpPath = "/backend-api/subscriptions/auto_top_up/settings"

    public init(coordinator: CodexAuthCoordinator) {
        self.coordinator = coordinator
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    public func fetchUsage() async throws -> CodexUsage {
        let context: CodexAccessContext
        do {
            context = try await coordinator.accessContext()
        } catch let error as NetworkError {
            recordAttempt(
                source: .unknown,
                httpStatus: error.httpStatus,
                category: Self.errorCategory(for: error)
            )
            throw error
        } catch {
            recordAttempt(source: .unknown, httpStatus: nil, category: .network)
            throw error
        }

        var req = URLRequest(url: baseURL.appendingPathComponent(usagePath))
        req.httpMethod = "GET"
        req.setValue("Bearer \(context.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://chatgpt.com/codex/settings/usage", forHTTPHeaderField: "Referer")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let accountID = context.accountID {
            req.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            recordAttempt(source: context.source, httpStatus: nil, category: .network)
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            recordAttempt(source: context.source, httpStatus: nil, category: .network)
            throw NetworkError.networkUnavailable
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401:
            if context.source == .codexOAuth {
                await coordinator.disableOAuthForSession()
            }
            recordAttempt(source: context.source, httpStatus: http.statusCode, category: .authFailed)
            throw NetworkError.tokenExpired
        case 429:
            recordAttempt(source: context.source, httpStatus: http.statusCode, category: .rateLimited)
            throw NetworkError.rateLimited
        default:
            recordAttempt(
                source: context.source,
                httpStatus: http.statusCode,
                category: (500...599).contains(http.statusCode) ? .serverError : .invalidResponse
            )
            throw NetworkError.httpError(statusCode: http.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let raw = try decoder.decode(WhamUsageResponse.self, from: data)
            recordAttempt(source: context.source, httpStatus: http.statusCode, category: .success)
            return CodexUsage(from: raw)
        } catch {
            recordAttempt(source: context.source, httpStatus: http.statusCode, category: .invalidResponse)
            let preview = String(data: data.prefix(2000), encoding: .utf8) ?? "<non-UTF8>"
            logger.error("[OpenAIClient] decodingError: \(error) | body: \(preview)")
            throw NetworkError.decodingError(underlying: error)
        }
    }

    public func fetchAutoReload() async throws -> CodexAutoReload {
        let context = try await coordinator.accessContext()

        var req = URLRequest(url: baseURL.appendingPathComponent(autoTopUpPath))
        req.httpMethod = "GET"
        req.setValue("Bearer \(context.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://chatgpt.com/codex/settings/usage", forHTTPHeaderField: "Referer")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let accountID = context.accountID {
            req.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await session.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.networkUnavailable
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401:
            if context.source == .codexOAuth {
                await coordinator.disableOAuthForSession()
            }
            throw NetworkError.tokenExpired
        case 429:
            throw NetworkError.rateLimited
        default:
            throw NetworkError.httpError(statusCode: http.statusCode)
        }

        let raw: AutoTopUpSettingsResponse
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            raw = try decoder.decode(AutoTopUpSettingsResponse.self, from: data)
        } catch {
            let preview = String(data: data.prefix(2000), encoding: .utf8) ?? "<non-UTF8>"
            logger.error("[OpenAIClient] fetchAutoReload decodingError: \(error) | body: \(preview)")
            throw NetworkError.decodingError(underlying: error)
        }

        guard let threshold = Double(raw.rechargeThreshold),
              let target    = Double(raw.rechargeTarget) else {
            logger.error("[OpenAIClient] fetchAutoReload: unparseable strings threshold=\(raw.rechargeThreshold) target=\(raw.rechargeTarget)")
            throw NetworkError.decodingError(underlying: AutoReloadParseError.stringToDouble)
        }
        return CodexAutoReload(isEnabled: raw.isEnabled, rechargeThreshold: threshold, rechargeTarget: target)
    }

    public func fetchBonusCreditsSpentThisMonth() async throws -> Double {
        let context = try await coordinator.accessContext()

        var req = URLRequest(url: baseURL.appendingPathComponent(creditUsageEventsPath))
        req.httpMethod = "GET"
        req.setValue("Bearer \(context.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://chatgpt.com/codex/settings/usage", forHTTPHeaderField: "Referer")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let accountID = context.accountID {
            req.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await session.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.networkUnavailable
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401:
            if context.source == .codexOAuth {
                await coordinator.disableOAuthForSession()
            }
            throw NetworkError.tokenExpired
        case 429:
            throw NetworkError.rateLimited
        default:
            throw NetworkError.httpError(statusCode: http.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let raw = try decoder.decode(CodexCreditUsageEventsResponse.self, from: data)
            return raw.monthToDateTotal()
        } catch {
            let preview = String(data: data.prefix(2000), encoding: .utf8) ?? "<non-UTF8>"
            logger.error("[OpenAIClient] fetchBonusCreditsSpentThisMonth decodingError: \(error) | body: \(preview)")
            throw NetworkError.decodingError(underlying: error)
        }
    }

    private func recordAttempt(
        source: CodexAuthSource,
        httpStatus: Int?,
        category: CodexSourceAttempt.ErrorCategory
    ) {
        SharedDefaults.appendCodexSourceAttempt(.init(
            source: source,
            httpStatus: httpStatus,
            errorCategory: category
        ))
    }

    private static func errorCategory(for error: NetworkError) -> CodexSourceAttempt.ErrorCategory {
        switch error {
        case .notAuthenticated, .tokenExpired, .refreshFailed:
            .authFailed
        case .rateLimited:
            .rateLimited
        case .decodingError:
            .invalidResponse
        case .networkUnavailable:
            .network
        case .httpError(let statusCode):
            (500...599).contains(statusCode) ? .serverError : .invalidResponse
        case .unknownEndpoint:
            .invalidResponse
        }
    }
}

private enum AutoReloadParseError: Error {
    case stringToDouble
}

private extension NetworkError {
    var httpStatus: Int? {
        switch self {
        case .notAuthenticated:
            401
        case .rateLimited:
            429
        case .httpError(let statusCode):
            statusCode
        default:
            nil
        }
    }
}
