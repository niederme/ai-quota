import Foundation
import OSLog

// MARK: - ClaudeClient

public actor ClaudeClient {
    private let coordinator: ClaudeAuthCoordinator
    private let session: URLSession
    private let baseURL = URL(string: "https://claude.ai")!
    private let logger = Logger(subsystem: "app.aiquota", category: "ClaudeClient")
    private var oauthPolicyFailures = 0
    private var oauthDisabledForSession = false

    public init(coordinator: ClaudeAuthCoordinator) {
        self.coordinator = coordinator
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    public func fetchUsage() async throws -> ClaudeUsage {
        if !oauthDisabledForSession {
            do {
                let oauth = try await coordinator.loadOAuthCredentials(allowKeychain: false)
                do {
                    let usage = try await fetchOAuthUsage(credentials: oauth)
                    oauthPolicyFailures = 0
                    recordAttempt(source: .oauth, httpStatus: 200, category: .success)
                    return usage
                } catch let error as ClaudeOAuthFetchError {
                    switch error {
                    case .unauthorized(let status, let policyBlocked):
                        await coordinator.invalidateCachedOAuthCredentials()
                        if policyBlocked {
                            oauthDisabledForSession = true
                            await coordinator.disableOAuthForSession()
                        } else if status == 403 {
                            oauthPolicyFailures += 1
                            if oauthPolicyFailures >= 3 {
                                oauthDisabledForSession = true
                                await coordinator.disableOAuthForSession()
                            }
                        } else if status == 401 {
                            oauthDisabledForSession = true
                            await coordinator.disableOAuthForSession()
                        }
                        recordAttempt(
                            source: .oauth,
                            httpStatus: status,
                            category: policyBlocked ? .policyBlocked : .authFailed
                        )
                    case .rateLimited:
                        recordAttempt(source: .oauth, httpStatus: 429, category: .rateLimited)
                        throw NetworkError.rateLimited
                    case .invalidResponse(let status):
                        recordAttempt(source: .oauth, httpStatus: status, category: .invalidResponse)
                        throw NetworkError.decodingError(underlying: error)
                    case .serverError(let status):
                        recordAttempt(source: .oauth, httpStatus: status, category: .serverError)
                        throw NetworkError.httpError(statusCode: status)
                    case .networkError(let underlying):
                        recordAttempt(source: .oauth, httpStatus: nil, category: .network)
                        throw underlying
                    }
                }
            } catch let error as ClaudeOAuthCredentialsError {
                recordAttempt(source: .oauth, httpStatus: nil, category: Self.errorCategory(for: error))
            } catch {
                recordAttempt(source: .oauth, httpStatus: nil, category: .malformedCredentials)
            }
        }

        let ctx = try await coordinator.requestContext()
        do {
            let usage = try await fetchUsageData(path: "/api/organizations/\(ctx.orgId)/usage")
            recordAttempt(source: .web, httpStatus: 200, category: .success)
            return usage
        } catch let error as NetworkError {
            recordAttempt(source: .web, httpStatus: error.httpStatus, category: Self.errorCategory(for: error))
            throw error
        } catch {
            recordAttempt(source: .web, httpStatus: nil, category: .network)
            throw error
        }
    }

    // MARK: - Private

    private func fetchOAuthUsage(credentials: ClaudeOAuthCredentials) async throws -> ClaudeUsage {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw ClaudeOAuthFetchError.invalidResponse(status: nil)
            }
            switch http.statusCode {
            case 200...299:
                let raw = try Self.decoder.decode(ClaudeOAuthUsageResponse.self, from: data)
                return Self.buildUsage(
                    from: raw,
                    planLabel: ClaudePlan.label(
                        subscriptionType: credentials.subscriptionType,
                        rateLimitTier: credentials.rateLimitTier
                    ),
                    source: .oauth
                )
            case 401, 403:
                throw ClaudeOAuthFetchError.unauthorized(
                    status: http.statusCode,
                    policyBlocked: Self.isPolicyBlockedResponse(data)
                )
            case 429:
                throw ClaudeOAuthFetchError.rateLimited
            default:
                throw ClaudeOAuthFetchError.serverError(http.statusCode)
            }
        } catch let error as ClaudeOAuthFetchError {
            throw error
        } catch is DecodingError {
            throw ClaudeOAuthFetchError.invalidResponse(status: nil)
        } catch {
            throw ClaudeOAuthFetchError.networkError(error)
        }
    }

    private func fetchUsageData(path: String) async throws -> ClaudeUsage {
        let req = makeRequest(path: path)

        // Use the async URLSession API so cooperative cancellation works correctly.
        // When the enclosing Task is cancelled (e.g. startAutoRefresh() restarts the
        // loop), the URLSession request is cancelled and URLError.cancelled is thrown.
        // refreshClaude() already handles URLError.cancelled silently, so isClaudeLoading
        // is always reset via defer and the spinner never gets stuck.
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            logger.error("[ClaudeClient] session error: \(error)")
            throw error
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        logger.info("[ClaudeClient] GET \(path) → HTTP \(status)")
        if status != 200 {
            let headers = (response as? HTTPURLResponse)?.allHeaderFields ?? [:]
            logger.warning("[ClaudeClient] non-200 headers: \(headers as NSDictionary)")
        }

        try checkStatus(response, data: data)

        do {
            let raw = try Self.decoder.decode(ClaudeUsageResponse.self, from: data)
            return Self.buildUsage(from: raw, planLabel: nil, source: .web)
        } catch {
            let preview = String(data: data.prefix(2000), encoding: .utf8) ?? "<non-utf8>"
            logger.error("[ClaudeClient] decodingError: \(error) | body: \(preview)")
            throw NetworkError.decodingError(underlying: error)
        }
    }

    // ISO 8601 with fractional seconds, e.g. "2026-03-18T22:00:01.194181+00:00"
    // Stored as a static let so the @Sendable date-decoding closure doesn't
    // capture a locally-allocated (non-Sendable) ISO8601DateFormatter instance.
    private nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = ClaudeClient.iso8601Formatter.date(from: str) {
                return date
            }
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            guard let date = fallback.date(from: str) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Invalid ISO8601 date: \(str)"
                )
            }
            return date
        }
        return d
    }

    private func makeRequest(path: String) -> URLRequest {
        let url = URL(string: "https://claude.ai\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        req.setValue("1.0.0", forHTTPHeaderField: "anthropic-client-version")
        if let deviceId = cookie(named: "anthropic-device-id") {
            req.setValue(deviceId, forHTTPHeaderField: "anthropic-device-id")
        }
        if let anonId = cookie(named: "ajs_anonymous_id") {
            req.setValue(anonId, forHTTPHeaderField: "anthropic-anonymous-id")
        }
        if let sessionId = cookie(named: "activitySessionId") {
            req.setValue(sessionId, forHTTPHeaderField: "x-activity-session-id")
        }
        return req
    }

    private func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.networkUnavailable
        }
        switch http.statusCode {
        case 200...299: break
        case 401, 403:  throw NetworkError.notAuthenticated
        case 429:       throw NetworkError.rateLimited
        default:        throw NetworkError.httpError(statusCode: http.statusCode)
        }
    }

    private func cookie(named name: String) -> String? {
        HTTPCookieStorage.shared.cookies?
            .first { $0.name == name && $0.domain.contains("claude.ai") }?
            .value
    }

    // MARK: - Response → model

    nonisolated static func _decodeUsageForTesting(
        _ data: Data,
        planLabel: ClaudeUsage.PlanLabel? = nil,
        source: ClaudeUsage.Source = .unknown,
        fetchedAt: Date
    ) throws -> ClaudeUsage {
        let raw = try decoder.decode(ClaudeUsageResponse.self, from: data)
        return buildUsage(from: raw, planLabel: planLabel, source: source, fetchedAt: fetchedAt)
    }

    private nonisolated static func buildUsage(
        from raw: ClaudeUsageResponse,
        planLabel: ClaudeUsage.PlanLabel?,
        source: ClaudeUsage.Source,
        fetchedAt: Date = .now
    ) -> ClaudeUsage {
        let sevenDay = raw.preferredSevenDayWindow
        let hasNormalWindow = raw.fiveHour?.utilization != nil || sevenDay?.utilization != nil
        let spendLimit = Self.spendLimit(from: raw.extraUsage, source: source, planLabel: planLabel, hasNormalWindow: hasNormalWindow)
        let extra: ClaudeUsage.ExtraUsage? = spendLimit == nil ? Self.extraUsage(from: raw.extraUsage) : nil
        let bonusUsage: ClaudeUsage.BonusUsage? = spendLimit == nil
            ? Self.bonusUsage(from: raw.extraUsage, source: source)
            : nil
        return ClaudeUsage(
            fiveHourUtilization: raw.fiveHour?.utilization,
            fiveHourResetsAt: raw.fiveHour?.resetsAt,
            sevenDayUtilization: sevenDay?.utilization,
            sevenDayResetsAt: sevenDay?.resetsAt,
            extraUsage: extra,
            bonusUsage: bonusUsage,
            spendLimit: spendLimit,
            planLabel: planLabel,
            source: source,
            fetchedAt: fetchedAt
        )
    }

    private static func bonusUsage(
        from raw: ClaudeUsageResponse.ExtraUsageBucket?,
        source: ClaudeUsage.Source
    ) -> ClaudeUsage.BonusUsage? {
        guard let raw,
              let usedCredits = raw.usedCredits
        else { return nil }

        let divisor = source == .web && raw.currency != nil ? 100.0 : 1.0
        let spent = usedCredits / divisor
        let limit = raw.monthlyLimit.map { $0 / divisor }
        let utilization = raw.utilization ?? limit.map { $0 > 0 ? (spent / $0) * 100 : 0 }

        return ClaudeUsage.BonusUsage(
            spent: spent,
            monthlyLimit: limit,
            utilization: utilization,
            currencyCode: raw.currency
        )
    }

    private static func extraUsage(from raw: ClaudeUsageResponse.ExtraUsageBucket?) -> ClaudeUsage.ExtraUsage? {
        guard let raw,
              let monthlyLimit = raw.monthlyLimit,
              let usedCredits = raw.usedCredits
        else { return nil }
        let utilization = raw.utilization ?? (monthlyLimit > 0 ? (usedCredits / Double(monthlyLimit)) * 100 : 0)
        return ClaudeUsage.ExtraUsage(
            isEnabled: raw.isEnabled ?? false,
            monthlyLimit: Int(monthlyLimit.rounded()),
            usedCredits: usedCredits,
            utilization: utilization
        )
    }

    private static func spendLimit(
        from raw: ClaudeUsageResponse.ExtraUsageBucket?,
        source: ClaudeUsage.Source,
        planLabel: ClaudeUsage.PlanLabel?,
        hasNormalWindow: Bool
    ) -> ClaudeUsage.SpendLimit? {
        guard let raw,
              let monthlyLimit = raw.monthlyLimit,
              let usedCredits = raw.usedCredits
        else { return nil }
        guard planLabel == .enterprise || !hasNormalWindow else { return nil }
        let divisor = source == .web ? 100.0 : 1.0
        let used = usedCredits / divisor
        let limit = monthlyLimit / divisor
        let utilization = raw.utilization ?? (limit > 0 ? (used / limit) * 100 : 0)
        return ClaudeUsage.SpendLimit(used: used, limit: limit, utilization: utilization, currencyCode: raw.currency)
    }

    private func recordAttempt(
        source: ClaudeUsage.Source,
        httpStatus: Int?,
        category: ClaudeSourceAttempt.ErrorCategory
    ) {
        SharedDefaults.appendClaudeSourceAttempt(.init(
            source: source,
            httpStatus: httpStatus,
            errorCategory: category
        ))
    }

    private static func isPolicyBlockedResponse(_ data: Data) -> Bool {
        guard let body = String(data: data.prefix(4000), encoding: .utf8)?.lowercased() else {
            return false
        }
        return body.contains("policy")
            || body.contains("disallowed")
            || body.contains("third-party")
            || body.contains("third party")
            || body.contains("not allowed")
            || body.contains("unsupported")
    }

    private static func errorCategory(for error: ClaudeOAuthCredentialsError) -> ClaudeSourceAttempt.ErrorCategory {
        switch error {
        case .notFound:
            .missingCredentials
        case .expired:
            .expiredCredentials
        case .missingScope:
            .missingScope
        case .decodeFailed, .missingOAuth, .missingAccessToken:
            .malformedCredentials
        }
    }

    private static func errorCategory(for error: NetworkError) -> ClaudeSourceAttempt.ErrorCategory {
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

// MARK: - Raw response shape

/// Mirrors the confirmed JSON structure of GET /api/organizations/{org}/usage.
/// All top-level fields are optional so new or removed fields don't break decoding.
private struct ClaudeUsageResponse: Decodable {
    let fiveHour:  WindowBucket?
    let sevenDay:  WindowBucket?
    let extraUsage: ExtraUsageBucket?

    /// Nullable per-model buckets. Some Team/Max responses omit `seven_day`
    /// but still expose a model-specific weekly window we can display.
    let sevenDayOauthApps: WindowBucket?
    let sevenDayOpus:      WindowBucket?
    let sevenDaySonnet:    WindowBucket?
    let sevenDayCowork:    WindowBucket?

    var preferredSevenDayWindow: WindowBucket? {
        [
            sevenDay,
            sevenDayOauthApps,
            sevenDaySonnet,
            sevenDayOpus,
            sevenDayCowork
        ].compactMap { $0 }.first { $0.utilization != nil }
    }

    struct WindowBucket: Decodable {
        let utilization: Double?
        let resetsAt: Date?
    }

    struct ExtraUsageBucket: Decodable {
        let isEnabled: Bool?
        let monthlyLimit: Double?
        let usedCredits: Double?
        let utilization: Double?
        let currency: String?
    }
}

private typealias ClaudeOAuthUsageResponse = ClaudeUsageResponse

private enum ClaudeOAuthFetchError: Error {
    case unauthorized(status: Int, policyBlocked: Bool)
    case rateLimited
    case invalidResponse(status: Int?)
    case serverError(Int)
    case networkError(Error)
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
