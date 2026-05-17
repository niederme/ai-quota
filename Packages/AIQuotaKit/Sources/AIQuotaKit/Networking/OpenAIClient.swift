import Foundation
import OSLog

public actor OpenAIClient {
    private let logger = Logger(subsystem: "app.aiquota", category: "OpenAIClient")
    private let coordinator: CodexAuthCoordinator
    private let session: URLSession

    private let baseURL = URL(string: "https://chatgpt.com")!
    // Confirmed endpoint from network inspection of chatgpt.com/codex/settings/usage
    private let usagePath = "/backend-api/wham/usage"
    private let autoTopUpPath = "/backend-api/subscriptions/auto_top_up/settings"

    public init(coordinator: CodexAuthCoordinator) {
        self.coordinator = coordinator
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    public func fetchUsage() async throws -> CodexUsage {
        let context = try await coordinator.accessContext()

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
            let raw = try decoder.decode(WhamUsageResponse.self, from: data)
            return CodexUsage(from: raw)
        } catch {
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
}

private enum AutoReloadParseError: Error {
    case stringToDouble
}
