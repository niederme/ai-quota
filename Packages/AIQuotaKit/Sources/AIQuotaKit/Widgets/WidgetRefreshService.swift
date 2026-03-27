import Foundation

public struct WidgetRefreshSnapshot: Sendable {
    public let codexUsage: CodexUsage?
    public let claudeUsage: ClaudeUsage?

    public init(codexUsage: CodexUsage?, claudeUsage: ClaudeUsage?) {
        self.codexUsage = codexUsage
        self.claudeUsage = claudeUsage
    }
}

public actor WidgetRefreshService {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpShouldSetCookies = false
        self.session = URLSession(configuration: configuration)
    }

    public func currentSnapshot() -> WidgetRefreshSnapshot {
        WidgetRefreshSnapshot(
            codexUsage: SharedDefaults.loadCachedUsage(),
            claudeUsage: SharedDefaults.loadCachedClaudeUsage()
        )
    }

    public func refreshAvailableServices(force: Bool = false, now: Date = .now) async -> WidgetRefreshSnapshot {
        var snapshot = currentSnapshot()
        guard force || WidgetRefreshPolicy.shouldFetchFromNetwork(
            codex: snapshot.codexUsage,
            claude: snapshot.claudeUsage,
            now: now
        ) else {
            return snapshot
        }

        async let codex = refreshCodexIfPossible(now: now)
        async let claude = refreshClaudeIfPossible(now: now)

        if let codexUsage = await codex {
            snapshot = WidgetRefreshSnapshot(codexUsage: codexUsage, claudeUsage: snapshot.claudeUsage)
        } else if SharedAuthContextStore.loadCodex() == nil {
            snapshot = WidgetRefreshSnapshot(codexUsage: SharedDefaults.loadCachedUsage(), claudeUsage: snapshot.claudeUsage)
        }

        if let claudeUsage = await claude {
            snapshot = WidgetRefreshSnapshot(codexUsage: snapshot.codexUsage, claudeUsage: claudeUsage)
        } else if SharedAuthContextStore.loadClaude() == nil {
            snapshot = WidgetRefreshSnapshot(codexUsage: snapshot.codexUsage, claudeUsage: SharedDefaults.loadCachedClaudeUsage())
        }

        return snapshot
    }

    private func refreshCodexIfPossible(now: Date) async -> CodexUsage? {
        guard var context = SharedAuthContextStore.loadCodex() else { return nil }

        do {
            let accessToken: String
            if context.hasUsableAccessToken(at: now), let cachedToken = context.accessToken {
                accessToken = cachedToken
            } else {
                accessToken = try await refreshCodexAccessToken(using: context.sessionToken)
                context = SharedCodexAuthContext(
                    sessionToken: context.sessionToken,
                    accessToken: accessToken,
                    accessTokenExpiresAt: now.addingTimeInterval(3600)
                )
                SharedAuthContextStore.saveCodex(context)
            }

            let usage = try await fetchCodexUsage(accessToken: accessToken)
            SharedDefaults.saveUsage(usage)
            return usage
        } catch let error as NetworkError {
            if error.isAuthError {
                SharedAuthContextStore.clearCodex()
                SharedDefaults.clearUsage()
            }
            return nil
        } catch {
            return nil
        }
    }

    private func refreshClaudeIfPossible(now: Date) async -> ClaudeUsage? {
        guard let context = SharedAuthContextStore.loadClaude() else { return nil }

        do {
            let usage = try await fetchClaudeUsage(orgId: context.orgId, cookies: context.httpCookies, now: now)
            SharedDefaults.saveClaudeUsage(usage)
            return usage
        } catch let error as NetworkError {
            if error.isAuthError {
                SharedAuthContextStore.clearClaude()
                SharedDefaults.clearClaudeUsage()
            }
            return nil
        } catch {
            return nil
        }
    }

    private func refreshCodexAccessToken(using sessionToken: String) async throws -> String {
        guard !sessionToken.isEmpty else { throw NetworkError.notAuthenticated }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/api/auth/session")!)
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        request.setValue("__Secure-next-auth.session-token=\(sessionToken)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.networkUnavailable }
        guard http.statusCode == 200 else {
            throw http.statusCode == 401 ? NetworkError.tokenExpired : NetworkError.refreshFailed
        }

        struct SessionResponse: Decodable {
            let accessToken: String
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SessionResponse.self, from: data).accessToken
    }

    private func fetchCodexUsage(accessToken: String) async throws -> CodexUsage {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://chatgpt.com/codex/settings/usage", forHTTPHeaderField: "Referer")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.networkUnavailable
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401:
            throw NetworkError.tokenExpired
        case 429:
            throw NetworkError.rateLimited
        default:
            throw NetworkError.httpError(statusCode: http.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let raw = try decoder.decode(WhamUsageResponse.self, from: data)
            return CodexUsage(from: raw)
        } catch {
            throw NetworkError.decodingError(underlying: error)
        }
    }

    private func fetchClaudeUsage(orgId: String, cookies: [HTTPCookie], now: Date) async throws -> ClaudeUsage {
        guard !cookies.isEmpty else { throw NetworkError.notAuthenticated }

        var request = URLRequest(url: URL(string: "https://claude.ai/api/organizations/\(orgId)/usage")!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        request.setValue("1.0.0", forHTTPHeaderField: "anthropic-client-version")
        HTTPCookie.requestHeaderFields(with: cookies).forEach { request.setValue($1, forHTTPHeaderField: $0) }

        if let deviceId = cookie(named: "anthropic-device-id", in: cookies) {
            request.setValue(deviceId, forHTTPHeaderField: "anthropic-device-id")
        }
        if let anonId = cookie(named: "ajs_anonymous_id", in: cookies) {
            request.setValue(anonId, forHTTPHeaderField: "anthropic-anonymous-id")
        }
        if let sessionId = cookie(named: "activitySessionId", in: cookies) {
            request.setValue(sessionId, forHTTPHeaderField: "x-activity-session-id")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.networkUnavailable
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw NetworkError.notAuthenticated
        case 429:
            throw NetworkError.rateLimited
        default:
            throw NetworkError.httpError(statusCode: http.statusCode)
        }

        do {
            let raw = try Self.claudeDecoder.decode(ClaudeWidgetUsageResponse.self, from: data)
            let extra = raw.extraUsage.map {
                ClaudeUsage.ExtraUsage(
                    isEnabled: $0.isEnabled,
                    monthlyLimit: $0.monthlyLimit,
                    usedCredits: $0.usedCredits,
                    utilization: $0.utilization
                )
            }

            return ClaudeUsage(
                fiveHourUtilization: raw.fiveHour?.utilization ?? 0,
                fiveHourResetsAt: raw.fiveHour?.resetsAt ?? now.addingTimeInterval(18_000),
                sevenDayUtilization: raw.sevenDay?.utilization ?? 0,
                sevenDayResetsAt: raw.sevenDay?.resetsAt ?? now.addingTimeInterval(604_800),
                extraUsage: extra,
                fetchedAt: now
            )
        } catch {
            throw NetworkError.decodingError(underlying: error)
        }
    }

    private func cookie(named name: String, in cookies: [HTTPCookie]) -> String? {
        cookies.first { $0.name == name && $0.domain.contains("claude.ai") }?.value
    }

    private nonisolated(unsafe) static let claudeISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let claudeDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { container in
            let single = try container.singleValueContainer()
            let value = try single.decode(String.self)
            guard let date = claudeISO8601Formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: single,
                    debugDescription: "Invalid ISO8601 date: \(value)"
                )
            }
            return date
        }
        return decoder
    }()
}

private struct ClaudeWidgetUsageResponse: Decodable {
    let fiveHour: ClaudeWindowBucket?
    let sevenDay: ClaudeWindowBucket?
    let extraUsage: ClaudeExtraUsageBucket?
}

private struct ClaudeWindowBucket: Decodable {
    let utilization: Double
    let resetsAt: Date?
}

private struct ClaudeExtraUsageBucket: Decodable {
    let isEnabled: Bool
    let monthlyLimit: Int
    let usedCredits: Double
    let utilization: Double
}
