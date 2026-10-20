import Foundation
import MobileAccessCore
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

    /// Returns the organization that would be used for cookie-authenticated
    /// enterprise detail requests. OAuth-only sessions intentionally have no
    /// organization scope and therefore cannot load these optional details.
    public func enterpriseDetailScopeID(requiresOAuthMatch: Bool) async throws -> String {
        let webOrganizationID = try Self.validatedEnterpriseOrganizationID(
            await coordinator.requestContext().orgId
        )
        guard requiresOAuthMatch else { return webOrganizationID }
        let credentials = try await coordinator.loadOAuthCredentials(allowKeychain: false)
        guard let rawOAuthOrganizationID = try await oauthOrganizationID(credentials: credentials),
              let oauthOrganizationID = try? Self.validatedEnterpriseOrganizationID(rawOAuthOrganizationID),
              oauthOrganizationID.caseInsensitiveCompare(webOrganizationID) == .orderedSame
        else {
            throw ClaudeEnterpriseDetailError.accountScopeUnavailable
        }
        return webOrganizationID
    }

    public func fetchEnterpriseSpend(
        period: ClaudeEnterprisePeriod
    ) async throws -> ScopedClaudeEnterpriseSpend {
        let context = try await coordinator.requestContext()
        let organizationID = try Self.validatedEnterpriseOrganizationID(context.orgId)
        let path = enterprisePath(
            organizationID: organizationID,
            resource: "spend",
            period: period,
            extraQuery: "&group_by=product_surface&granularity=daily"
        )
        let data = try await fetchWebData(path: path)
        return try Self._decodeEnterpriseSpendForTesting(
            data,
            scopeID: organizationID,
            period: period,
            fetchedAt: .now
        )
    }

    public func fetchEnterpriseSkills(
        period: ClaudeEnterprisePeriod
    ) async throws -> ScopedClaudeEnterpriseSkills {
        let context = try await coordinator.requestContext()
        let organizationID = try Self.validatedEnterpriseOrganizationID(context.orgId)
        let path = enterprisePath(
            organizationID: organizationID,
            resource: "skills",
            period: period
        )
        let data = try await fetchWebData(path: path)
        return try Self._decodeEnterpriseSkillsForTesting(
            data,
            scopeID: organizationID,
            period: period,
            fetchedAt: .now
        )
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
                    source: .oauth,
                    weeklyBreakdown: Self.weeklyBreakdown(from: data)
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
        logger.info("[ClaudeClient] usage request → HTTP \(status)")

        try checkStatus(response, data: data)

        do {
            let raw = try Self.decoder.decode(ClaudeUsageResponse.self, from: data)
            return Self.buildUsage(from: raw, planLabel: nil, source: .web, weeklyBreakdown: Self.weeklyBreakdown(from: data))
        } catch {
            logger.error("[ClaudeClient] usage response decoding failed")
            throw NetworkError.decodingError(underlying: error)
        }
    }

    private func fetchWebData(path: String) async throws -> Data {
        let request = makeRequest(path: path)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw error
        }
        try checkStatus(response, data: data)
        return data
    }

    private func enterprisePath(
        organizationID: String,
        resource: String,
        period: ClaudeEnterprisePeriod,
        extraQuery: String = ""
    ) -> String {
        let safeOrganizationID = organizationID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? organizationID
        return "/api/organizations/\(safeOrganizationID)/usage/\(resource)"
            + "?start_date=\(Self.apiDateString(period.startDate))"
            + "&end_date=\(Self.apiDateString(period.endDate))"
            + extraQuery
    }

    static func _validatedEnterpriseOrganizationIDForTesting(_ organizationID: String) throws -> String {
        try validatedEnterpriseOrganizationID(organizationID)
    }

    private nonisolated static func validatedEnterpriseOrganizationID(
        _ organizationID: String
    ) throws -> String {
        guard let uuid = UUID(uuidString: organizationID) else {
            throw ClaudeEnterpriseDetailError.accountScopeUnavailable
        }
        return uuid.uuidString.lowercased()
    }

    private nonisolated static func apiDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func oauthOrganizationID(
        credentials: ClaudeOAuthCredentials
    ) async throws -> String? {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.networkUnavailable
        }
        guard (200...299).contains(http.statusCode) else {
            throw NetworkError.httpError(statusCode: http.statusCode)
        }
        return ClaudeAPI.decodeOrganizationID(data)
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
        return buildUsage(from: raw, planLabel: planLabel, source: source, fetchedAt: fetchedAt, weeklyBreakdown: weeklyBreakdown(from: data))
    }

    public nonisolated static func _decodeEnterpriseSpendForTesting(
        _ data: Data,
        scopeID: String,
        period: ClaudeEnterprisePeriod,
        fetchedAt: Date
    ) throws -> ScopedClaudeEnterpriseSpend {
        ScopedClaudeEnterpriseSpend(
            report: try JSONDecoder().decode(ClaudeSpendHistory.self, from: data),
            scopeID: scopeID,
            period: period,
            fetchedAt: fetchedAt
        )
    }

    public nonisolated static func _decodeEnterpriseSkillsForTesting(
        _ data: Data,
        scopeID: String,
        period: ClaudeEnterprisePeriod,
        fetchedAt: Date
    ) throws -> ScopedClaudeEnterpriseSkills {
        ScopedClaudeEnterpriseSkills(
            report: try JSONDecoder().decode(ClaudeEnterpriseSkillsResponse.self, from: data),
            scopeID: scopeID,
            period: period,
            fetchedAt: fetchedAt
        )
    }

    private nonisolated static func weeklyBreakdown(from data: Data) -> ClaudeWeeklyBreakdown? {
        // The shared decoder uses explicit API keys; keep it separate from the
        // allowance decoder's convertFromSnakeCase strategy. Invalid optional
        // analytics must not discard a valid allowance reading.
        struct Envelope: Decodable { let seven_day_breakdown: ClaudeWeeklyBreakdown? }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.seven_day_breakdown
    }

    private nonisolated static func buildUsage(
        from raw: ClaudeUsageResponse,
        planLabel: ClaudeUsage.PlanLabel?,
        source: ClaudeUsage.Source,
        fetchedAt: Date = .now,
        weeklyBreakdown: ClaudeWeeklyBreakdown? = nil
    ) -> ClaudeUsage {
        let sevenDay = raw.preferredSevenDayWindow
        let hasNormalWindow = raw.fiveHour?.utilization != nil || sevenDay?.utilization != nil
        let spendLimit = Self.spendLimit(from: raw.extraUsage, source: source, planLabel: planLabel, hasNormalWindow: hasNormalWindow)
        let extra: ClaudeUsage.ExtraUsage? = spendLimit == nil ? Self.extraUsage(from: raw.extraUsage) : nil
        let bonusUsage: ClaudeUsage.BonusUsage? = spendLimit == nil
            ? Self.bonusUsage(from: raw.extraUsage, source: source)
            : nil
        let usageCredits = spendLimit == nil
            ? Self.usageCredits(from: raw.spend, fallback: bonusUsage, extraUsage: raw.extraUsage)
            : nil
        return ClaudeUsage(
            fiveHourUtilization: raw.fiveHour?.utilization,
            fiveHourResetsAt: raw.fiveHour?.resetsAt,
            sevenDayUtilization: sevenDay?.utilization,
            sevenDayResetsAt: sevenDay?.resetsAt,
            extraUsage: extra,
            bonusUsage: bonusUsage,
            usageCredits: usageCredits,
            spendLimit: spendLimit,
            planLabel: planLabel,
            source: source,
            fetchedAt: fetchedAt,
            weeklyBreakdown: weeklyBreakdown
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

    private static func usageCredits(
        from spend: ClaudeUsageResponse.SpendBucket?,
        fallback: ClaudeUsage.BonusUsage?,
        extraUsage: ClaudeUsageResponse.ExtraUsageBucket?
    ) -> ClaudeUsage.UsageCredits? {
        if let spend, let used = spend.used {
            return ClaudeUsage.UsageCredits(
                spent: used.amount,
                monthlyLimit: spend.limit?.amount,
                utilization: spend.limit == nil ? nil : spend.percent,
                currencyCode: used.currency,
                severity: .init(serverValue: spend.severity),
                isEnabled: spend.enabled ?? extraUsage?.isEnabled ?? true,
                limitReached: extraUsage?.spendLimitReached ?? false
            )
        }

        guard let fallback else { return nil }
        return ClaudeUsage.UsageCredits(
            spent: fallback.spent,
            monthlyLimit: fallback.monthlyLimit,
            utilization: fallback.utilization,
            currencyCode: fallback.currencyCode,
            isEnabled: extraUsage?.isEnabled ?? true,
            limitReached: extraUsage?.spendLimitReached
                ?? ((fallback.utilization ?? 0) >= 100)
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
    let spend: SpendBucket?

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
        let spendLimitReached: Bool?
    }

    struct SpendBucket: Decodable {
        let used: Money?
        let limit: Money?
        let percent: Double?
        let severity: String?
        let enabled: Bool?
    }

    struct Money: Decodable {
        let amountMinor: Double
        let currency: String?
        let exponent: Int

        var amount: Double {
            amountMinor / pow(10, Double(exponent))
        }
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

private enum ClaudeEnterpriseDetailError: Error {
    case accountScopeUnavailable
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
