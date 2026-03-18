import Foundation

// MARK: - ClaudeClient

/// Fetches quota / usage data from claude.ai.
///
/// Auth strategy: cookie-based (no Bearer token).
///   • sessionKey    — HttpOnly session cookie set by claude.ai after login
///   • lastActiveOrg — non-HttpOnly cookie containing the org UUID
///
/// Confirmed endpoint (verified via browser devtools on claude.ai/settings/usage):
///   GET /api/organizations/{org_uuid}/usage
///
/// Confirmed response shape (2026-03-18):
///   {
///     "five_hour":  { "utilization": 34.0, "resets_at": "2026-03-18T22:00:01.194181+00:00" },
///     "seven_day":  { "utilization": 30.0, "resets_at": "2026-03-23T17:00:00.194201+00:00" },
///     "extra_usage": { "is_enabled": true, "monthly_limit": 2000,
///                      "used_credits": 1609.0, "utilization": 80.45 },
///     "seven_day_oauth_apps": null,
///     "seven_day_opus": null,
///     "seven_day_sonnet": null,
///     "iguana_necktie": null   // internal A/B field, safe to ignore
///   }

public actor ClaudeClient {
    private let authManager: ClaudeAuthManager
    private let session: URLSession
    private let baseURL = URL(string: "https://claude.ai")!

    public init(authManager: ClaudeAuthManager) {
        self.authManager = authManager
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    public func fetchUsage() async throws -> ClaudeUsage {
        // Ensure all claude.ai WKWebView cookies are visible to URLSession
        await authManager.syncCookies()

        // Log all claude.ai cookies so we can diagnose sync issues
        let allCookies = HTTPCookieStorage.shared.cookies?
            .filter { $0.domain.contains("claude.ai") } ?? []
        print("[ClaudeClient] cookies after sync (\(allCookies.count)): \(allCookies.map { "\($0.name)(domain:\($0.domain))" })")

        // Org UUID lives in the lastActiveOrg cookie — no /account call needed
        guard let orgId = cookie(named: "lastActiveOrg"), !orgId.isEmpty else {
            print("[ClaudeClient] ❌ lastActiveOrg cookie not found — not authenticated")
            throw NetworkError.notAuthenticated
        }
        print("[ClaudeClient] orgId: \(orgId)")

        return try await fetchUsageData(path: "/api/organizations/\(orgId)/usage")
    }

    // MARK: - Private

    private func fetchUsageData(path: String) async throws -> ClaudeUsage {
        let req = makeRequest(path: path)
        print("[ClaudeClient] → \(req.url?.absoluteString ?? "nil") (already cancelled: \(Task.isCancelled))")

        // Use the callback-based dataTask API so the HTTP request is NOT automatically
        // cancelled when the Swift Task is cancelled (the async URLSession.data(for:)
        // throws URLError.cancelled immediately if Task.isCancelled is true).
        // The dataTask callback variant runs to completion regardless of task state.
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await withCheckedThrowingContinuation { cont in
                let task = session.dataTask(with: req) { data, resp, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else if let data, let resp {
                        cont.resume(returning: (data, resp))
                    } else {
                        cont.resume(throwing: URLError(.unknown))
                    }
                }
                task.resume()
            }
        } catch {
            print("[ClaudeClient] ❌ session error: \(error)")
            throw error
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("[ClaudeClient] GET \(path) → HTTP \(status)")
        if status != 200 {
            print("[ClaudeClient] response headers: \((response as? HTTPURLResponse)?.allHeaderFields ?? [:])")
        }

        try checkStatus(response, data: data)

        do {
            let raw = try Self.decoder.decode(ClaudeUsageResponse.self, from: data)
            return buildUsage(from: raw)
        } catch {
            print("[ClaudeClient] decode error: \(error)")
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
            guard let date = ClaudeClient.iso8601Formatter.date(from: str) else {
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
        default:        throw NetworkError.httpError(statusCode: http.statusCode)
        }
    }

    private func cookie(named name: String) -> String? {
        HTTPCookieStorage.shared.cookies?
            .first { $0.name == name && $0.domain.contains("claude.ai") }?
            .value
    }

    // MARK: - Response → model

    private func buildUsage(from raw: ClaudeUsageResponse) -> ClaudeUsage {
        let now = Date.now

        let extra: ClaudeUsage.ExtraUsage? = raw.extraUsage.map {
            ClaudeUsage.ExtraUsage(
                isEnabled: $0.isEnabled,
                monthlyLimit: $0.monthlyLimit,
                usedCredits: $0.usedCredits,
                utilization: $0.utilization
            )
        }

        return ClaudeUsage(
            fiveHourUtilization:  raw.fiveHour?.utilization ?? 0,
            fiveHourResetsAt:     raw.fiveHour?.resetsAt ?? now.addingTimeInterval(18_000),
            sevenDayUtilization:  raw.sevenDay?.utilization ?? 0,
            sevenDayResetsAt:     raw.sevenDay?.resetsAt ?? now.addingTimeInterval(604_800),
            extraUsage:           extra,
            fetchedAt:            now
        )
    }
}

// MARK: - Raw response shape

/// Mirrors the confirmed JSON structure of GET /api/organizations/{org}/usage.
/// All top-level fields are optional so new or removed fields don't break decoding.
private struct ClaudeUsageResponse: Decodable {
    let fiveHour:  WindowBucket?
    let sevenDay:  WindowBucket?
    let extraUsage: ExtraUsageBucket?

    /// Nullable per-model buckets (seven_day_opus, seven_day_sonnet, etc.)
    /// Declared so the decoder doesn't fail on unknown keys; values are unused.
    let sevenDayOauthApps: WindowBucket?
    let sevenDayOpus:      WindowBucket?
    let sevenDaySonnet:    WindowBucket?
    let sevenDayCowork:    WindowBucket?

    struct WindowBucket: Decodable {
        let utilization: Double
        let resetsAt: Date
    }

    struct ExtraUsageBucket: Decodable {
        let isEnabled: Bool
        let monthlyLimit: Int
        let usedCredits: Double
        let utilization: Double
    }
}
