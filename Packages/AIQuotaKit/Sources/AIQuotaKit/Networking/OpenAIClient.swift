import Foundation

public actor OpenAIClient {
    private let authManager: AuthManager
    private let session: URLSession

    private let baseURL = URL(string: "https://chatgpt.com")!
    // Confirmed endpoint from network inspection of chatgpt.com/codex/settings/usage
    private let usagePath = "/backend-api/wham/usage"

    public init(authManager: AuthManager) {
        self.authManager = authManager
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    public func fetchUsage() async throws -> CodexUsage {
        let token = try await authManager.accessToken

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
}
