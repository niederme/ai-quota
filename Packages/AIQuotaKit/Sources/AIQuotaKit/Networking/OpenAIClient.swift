import Foundation
import OSLog

public actor OpenAIClient {
    private let logger = Logger(subsystem: "app.aiquota", category: "OpenAIClient")
    private let coordinator: CodexAuthCoordinator
    private let session: URLSession

    private let baseURL = URL(string: "https://chatgpt.com")!
    // Confirmed endpoint from network inspection of chatgpt.com/codex/settings/usage
    private let usagePath = "/backend-api/wham/usage"
    private let autoReloadPath = "/backend-api/subscriptions/auto_top_up/settings"

    public init(coordinator: CodexAuthCoordinator) {
        self.coordinator = coordinator
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    public func fetchUsage() async throws -> CodexUsage {
        let token = try await coordinator.accessToken()

        var req = URLRequest(url: baseURL.appendingPathComponent(usagePath))
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://chatgpt.com/codex/settings/usage", forHTTPHeaderField: "Referer")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: req)

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
            let preview = String(data: data.prefix(2000), encoding: .utf8) ?? "<non-UTF8>"
            logger.error("[OpenAIClient] decodingError: \(error) | body: \(preview)")
            throw NetworkError.decodingError(underlying: error)
        }
    }

    public func fetchAutoReload() async throws -> CodexAutoReload {
        let token = try await coordinator.accessToken()

        var req = URLRequest(url: baseURL.appendingPathComponent(autoReloadPath))
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://chatgpt.com/codex/settings/usage", forHTTPHeaderField: "Referer")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: req)

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

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw: AutoTopUpSettingsResponse
        do {
            raw = try decoder.decode(AutoTopUpSettingsResponse.self, from: data)
        } catch {
            let preview = String(data: data.prefix(2000), encoding: .utf8) ?? "<non-UTF8>"
            logger.error("[OpenAIClient] autoReload decodingError: \(error) | body: \(preview)")
            throw NetworkError.decodingError(underlying: error)
        }
        guard let result = raw.toCodexAutoReload() else {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<non-UTF8>"
            logger.error("[OpenAIClient] autoReload: numeric fields missing/non-parseable | body: \(preview)")
            throw NetworkError.decodingError(underlying: DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "rechargeThreshold/rechargeTarget missing or non-numeric")
            ))
        }
        return result
    }
}
