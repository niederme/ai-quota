import Foundation
import CryptoKit
import Security

public enum ClaudeAccessError: Error, LocalizedError, Sendable {
    case invalidCode, expiredChallenge
    public var errorDescription: String? {
        switch self {
        case .invalidCode: "Paste the complete authorization code from the sign-in page for this connection."
        case .expiredChallenge: "This sign-in attempt expired. Start a new connection."
        }
    }
}

public struct ClaudeChallenge: Sendable {
    public let verifier: String
    public let state: String
    public let createdAt: Date
    public init(now: Date = .now) throws {
        func random() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw AccessError.invalidResponse
            }
            return Self.base64URL(Data(bytes))
        }
        verifier = try random()
        state = try random()
        createdAt = now
    }
    public var authorizationURL: URL {
        var url = URLComponents(string: "https://claude.ai/oauth/authorize")!
        url.queryItems = [
            .init(name: "code", value: "true"), .init(name: "client_id", value: ClaudeAPI.clientID),
            .init(name: "response_type", value: "code"), .init(name: "redirect_uri", value: ClaudeAPI.redirectURI),
            .init(name: "scope", value: ClaudeAPI.scopes),
            .init(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: state)
        ]
        return url.url!
    }
    public func code(from pasted: String, now: Date) throws -> String {
        guard now.timeIntervalSince(createdAt) >= 0, now.timeIntervalSince(createdAt) < 900 else {
            throw ClaudeAccessError.expiredChallenge
        }
        let parts = pasted.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "#", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1] == state, !parts[0].isEmpty,
              !parts[0].contains(where: { $0.isWhitespace }), parts[0].count < 4096 else {
            throw ClaudeAccessError.invalidCode
        }
        return String(parts[0])
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

public struct ClaudeTokens: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    public func needsRefresh(at now: Date) -> Bool { expiresAt <= now.addingTimeInterval(60) }
}

public struct ClaudeAPI: Sendable {
    // Published first-party CLI identity, not an AI Quota registration.
    // Personal technical probe; third-party permission remains unresolved.
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    // Deliberately omits inference. API-key creation authority is still broad;
    // the probe never calls the key-creation endpoint.
    public static let scopes = "org:create_api_key user:profile"
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = ProviderTransport()) { self.transport = transport }

    public func exchange(_ pasted: String, challenge: ClaudeChallenge, now: Date = .now) async throws -> ClaudeTokens {
        let code = try challenge.code(from: pasted, now: now)
        return try await tokenRequest(["grant_type": "authorization_code", "code": code,
            "state": challenge.state, "code_verifier": challenge.verifier,
            "redirect_uri": Self.redirectURI, "client_id": Self.clientID], previous: nil, now: now)
    }
    public func renew(_ tokens: ClaudeTokens, now: Date = .now) async throws -> ClaudeTokens {
        guard let refresh = tokens.refreshToken, !refresh.isEmpty else { throw AccessError.expired }
        return try await tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh,
            "client_id": Self.clientID, "scope": Self.scopes], previous: tokens, now: now)
    }
    private func tokenRequest(_ body: [String: String], previous: ClaudeTokens?, now: Date) async throws -> ClaudeTokens {
        var request = URLRequest(url: URL(string: "https://console.anthropic.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else { throw AccessError.http(response.status) }
        let raw = try JSONDecoder().decode(TokenResponse.self, from: response.data)
        guard !raw.access_token.isEmpty, raw.expires_in.isFinite, raw.expires_in > 0 else { throw AccessError.invalidResponse }
        return ClaudeTokens(accessToken: raw.access_token, refreshToken: raw.refresh_token ?? previous?.refreshToken,
                            expiresAt: now.addingTimeInterval(raw.expires_in))
    }
    public func usage(_ tokens: ClaudeTokens, now: Date? = nil) async throws -> QuotaReading {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("AIQuotaMobileProbe/0.1", forHTTPHeaderField: "User-Agent")
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else { throw AccessError.http(response.status) }
        return try Self.decodeUsage(response.data, now: now ?? .now)
    }
    public static func decodeUsage(_ data: Data, now: Date) throws -> QuotaReading {
        let raw = try JSONDecoder().decode(UsageResponse.self, from: data)
        func window(_ raw: Window?, duration: Int) throws -> QuotaWindow? {
            guard let raw, let used = raw.utilization else { return nil }
            guard used.isFinite, (0...100).contains(used) else { throw AccessError.invalidResponse }
            var reset: Date?
            if let text = raw.resets_at {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                reset = formatter.date(from: text)
                if reset == nil {
                    formatter.formatOptions = [.withInternetDateTime]
                    reset = formatter.date(from: text)
                }
                guard reset != nil else { throw AccessError.invalidResponse }
            }
            return QuotaWindow(usedPercent: used, durationSeconds: duration, resetsAt: reset)
        }
        let short = try window(raw.five_hour, duration: 18000)
        let weekly = try window(raw.seven_day, duration: 604800)
        guard short != nil || weekly != nil else { throw AccessError.noWindows }
        return QuotaReading(fetchedAt: now, shortTerm: short, weekly: weekly)
    }
    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
    }
    private struct UsageResponse: Decodable { let five_hour: Window?; let seven_day: Window? }
    private struct Window: Decodable { let utilization: Double?; let resets_at: String? }
}
