import Foundation
import CryptoKit
import OSLog
import MobileAccessCore

public actor OpenAIClient {
    private let logger = Logger(subsystem: "app.aiquota", category: "OpenAIClient")
    private let coordinator: CodexAuthCoordinator
    private let session: URLSession
    private let accountStorageID: UUID?

    private let baseURL = URL(string: "https://chatgpt.com")!
    // Confirmed endpoint from network inspection of chatgpt.com/codex/settings/usage
    private let usagePath = "/backend-api/wham/usage"
    private let creditUsageEventsPath = "/backend-api/wham/usage/credit-usage-events"
    private let autoTopUpPath = "/backend-api/subscriptions/auto_top_up/settings"

    public init(coordinator: CodexAuthCoordinator, accountStorageID: UUID? = nil) {
        self.coordinator = coordinator
        self.accountStorageID = accountStorageID
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        if accountStorageID != nil {
            // Scoped calls authenticate with this coordinator's bearer token.
            // A process-wide ChatGPT cookie could select a different account.
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
        }
        self.session = URLSession(configuration: config)
    }

    /// Opaque in-memory scope, never logged or persisted. Including the credential
    /// distinguishes users in a shared workspace; token rotation safely drops history.
    public func tokenHistoryScopeID() async throws -> String? {
        Self.tokenHistoryScope(for: try await coordinator.accessContext())
    }

    static func tokenHistoryScope(for context: CodexAccessContext) -> String {
        let identity = Data(((context.accountID ?? "") + ":" + context.accessToken).utf8)
        return SHA256.hash(data: identity).description
    }

    /// Optional profile history. Failures must not invalidate working quota authentication.
    public func fetchTokenHistory() async throws -> CodexTokenHistory? {
        let context = try await coordinator.accessContext()
        var request = URLRequest(url: baseURL.appendingPathComponent("/backend-api/profiles/me/page"))
        request.setValue("Bearer \(context.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = context.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.networkUnavailable }
        if http.statusCode == 403 || http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw NetworkError.httpError(statusCode: http.statusCode) }
        // Never log the private profile response, including on decoding failure.
        return try CodexTokenHistory.decode(data, scopeID: Self.tokenHistoryScope(for: context))
    }

    /// The same daily credit feed used by iOS service analytics. Optional history
    /// failures never change the working quota connection.
    public func fetchUsageHistory(now: Date = .now) async throws -> CodexUsageHistory {
        let context = try await coordinator.accessContext()
        var url = URLComponents(url: baseURL.appendingPathComponent("/backend-api/wham/usage/daily-token-usage-breakdown"), resolvingAgainstBaseURL: false)!
        url.queryItems = [
            URLQueryItem(name: "start_date", value: CodexUsageHistory.dateString(now.addingTimeInterval(-29 * 86400))),
            URLQueryItem(name: "end_date", value: CodexUsageHistory.dateString(now)),
            URLQueryItem(name: "group_by", value: "day")
        ]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 5
        request.setValue("Bearer \(context.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = context.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.networkUnavailable }
        guard http.statusCode == 200 else { throw NetworkError.httpError(statusCode: http.statusCode) }
        return try CodexUsageHistory.decode(data, now: now)
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

        let raw: WhamUsageResponse
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            raw = try decoder.decode(WhamUsageResponse.self, from: data)
        } catch {
            recordAttempt(source: context.source, httpStatus: http.statusCode, category: .invalidResponse)
            logger.error("[OpenAIClient] usage decoding failed: \(error)")
            throw NetworkError.decodingError(underlying: error)
        }
        recordAttempt(source: context.source, httpStatus: http.statusCode, category: .success)
        var usage = CodexUsage(from: raw)
        if usage.displayableMonthlyBudget == nil, usage.reportedWindowShape == nil,
           let accountID = context.accountID, !accountID.isEmpty,
           let budget = try? await fetchMemberMonthlyUsage(context: context, accountID: accountID).monthlyBudget {
            usage = usage.withMonthlyBudget(budget)
        }
        let previous = accountStorageID.map { SharedDefaults.loadCachedUsage(forAccountID: $0.uuidString) }
            ?? (accountStorageID == nil ? SharedDefaults.loadCachedUsage() : nil)
        return usage.retainingLastConfirmedWindows(from: previous)
    }

    /// Fetches the organization member monthly budget when the account exposes it.
    /// Personal accounts may return 404; callers can treat that as unavailable.
    public func fetchMemberMonthlyUsage() async throws -> CodexMonthlyUsageResponse {
        let context = try await coordinator.accessContext()
        guard let accountID = context.accountID, !accountID.isEmpty else {
            throw NetworkError.notAuthenticated
        }
        return try await fetchMemberMonthlyUsage(context: context, accountID: accountID)
    }

    private func fetchMemberMonthlyUsage(context: CodexAccessContext, accountID: String) async throws -> CodexMonthlyUsageResponse {
        var req = URLRequest(url: Self.memberMonthlyUsageURL(baseURL: baseURL, accountID: accountID))
        req.httpMethod = "GET"
        req.setValue("Bearer \(context.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.networkUnavailable }
        switch http.statusCode {
        case 200...299: break
        case 401: throw NetworkError.tokenExpired
        case 429: throw NetworkError.rateLimited
        default: throw NetworkError.httpError(statusCode: http.statusCode)
        }
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(CodexMonthlyUsageResponse.self, from: data)
        } catch {
            throw NetworkError.decodingError(underlying: error)
        }
    }

    nonisolated static func _decodeMonthlyUsageForTesting(_ data: Data) throws -> CodexMonthlyUsageResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CodexMonthlyUsageResponse.self, from: data)
    }

    nonisolated static func _memberMonthlyUsageURLForTesting(accountID: String) -> URL {
        memberMonthlyUsageURL(baseURL: URL(string: "https://chatgpt.com")!, accountID: accountID)
    }

    private static func memberMonthlyUsageURL(baseURL: URL, accountID: String) -> URL {
        baseURL
            .appendingPathComponent("backend-api")
            .appendingPathComponent("accounts")
            .appendingPathComponent(accountID)
            .appendingPathComponent("spend-controls")
            .appendingPathComponent("current-user")
            .appendingPathComponent("monthly-usage")
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
            logger.error("[OpenAIClient] fetchAutoReload decodingError: \(error)")
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
            logger.error("[OpenAIClient] fetchBonusCreditsSpentThisMonth decodingError: \(error)")
            throw NetworkError.decodingError(underlying: error)
        }
    }

    private func recordAttempt(
        source: CodexAuthSource,
        httpStatus: Int?,
        category: CodexSourceAttempt.ErrorCategory
    ) {
        // Source attempts are currently stored in one shared ring. Suppress
        // writes for scoped accounts until a per-account diagnostics store is
        // available, preventing cross-account history leakage.
        guard accountStorageID == nil else { return }
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
