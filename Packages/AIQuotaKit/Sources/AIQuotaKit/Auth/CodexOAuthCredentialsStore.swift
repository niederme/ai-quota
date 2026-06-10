import Foundation

public struct CodexOAuthCredentials: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let accountID: String?
    public let lastRefresh: Date?
    public let expiresAt: Date?

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}

public enum CodexOAuthCredentialsError: LocalizedError, Sendable {
    case notFound
    case decodeFailed
    case missingTokens
    case missingAccessToken
    case expired

    public var errorDescription: String? {
        switch self {
        case .notFound:
            "Codex CLI credentials not found. Run `codex` to sign in."
        case .decodeFailed:
            "Could not decode Codex CLI credentials."
        case .missingTokens:
            "Codex CLI credentials do not contain OAuth tokens."
        case .missingAccessToken:
            "Codex CLI credentials are missing an access token."
        case .expired:
            "Run `codex` to refresh your session."
        }
    }
}

public enum CodexOAuthCredentialsStore {
    public static func hasUsableCredentials(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> Bool {
        (try? loadUsable(env: env, fileManager: fileManager)) != nil
    }

    public static func loadUsable(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> CodexOAuthCredentials {
        let credentials = try load(env: env, fileManager: fileManager)
        guard !credentials.isExpired else { throw CodexOAuthCredentialsError.expired }
        return credentials
    }

    public static func load(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> CodexOAuthCredentials {
        let url = authURL(env: env, fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else {
            throw CodexOAuthCredentialsError.notFound
        }
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    public static func parse(data: Data) throws -> CodexOAuthCredentials {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let root = try? decoder.decode(Root.self, from: data) else {
            throw CodexOAuthCredentialsError.decodeFailed
        }
        guard let tokens = root.tokens else {
            throw CodexOAuthCredentialsError.missingTokens
        }
        let accessToken = (tokens.accessToken ?? tokens.access_token ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            throw CodexOAuthCredentialsError.missingAccessToken
        }
        let idToken = tokens.idToken ?? tokens.id_token
        let accountID = tokens.accountID
            ?? tokens.accountId
            ?? tokens.account_id
            ?? root.accountID
            ?? root.accountId
            ?? root.account_id
            ?? Self.jwtAccountID(idToken)
            ?? Self.jwtAccountID(accessToken)
        return CodexOAuthCredentials(
            accessToken: accessToken,
            refreshToken: tokens.refreshToken ?? tokens.refresh_token,
            idToken: idToken,
            accountID: accountID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            lastRefresh: Self.parseDate(root.lastRefresh ?? root.last_refresh),
            expiresAt: Self.jwtExpiry(accessToken)
        )
    }

    public static func authURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let codexHome = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !codexHome.isEmpty {
            return URL(fileURLWithPath: codexHome, isDirectory: true).appendingPathComponent("auth.json")
        }
        let home = env["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(".codex/auth.json")
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static func jwtExpiry(_ token: String) -> Date? {
        guard let json = jwtPayload(token),
              let exp = json["exp"] as? TimeInterval
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// Extracts the ChatGPT workspace account ID from a JWT's claims. Used for
    /// both Codex CLI credentials and web-session access tokens — Team accounts
    /// need this sent as `ChatGPT-Account-Id` or usage requests resolve against
    /// the wrong (often Codex-less) default workspace.
    static func jwtAccountID(_ token: String?) -> String? {
        guard let token, let json = jwtPayload(token) else { return nil }
        if let accountID = json["chatgpt_account_id"] as? String {
            return accountID
        }
        guard let auth = json["https://api.openai.com/auth"] as? [String: Any] else {
            return nil
        }
        return (auth["chatgpt_account_id"] as? String)
            ?? (auth["account_id"] as? String)
    }

    private static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private struct Root: Decodable {
        let tokens: Tokens?
        let lastRefresh: String?
        let last_refresh: String?
        let accountID: String?
        let accountId: String?
        let account_id: String?
    }

    private struct Tokens: Decodable {
        let accessToken: String?
        let access_token: String?
        let refreshToken: String?
        let refresh_token: String?
        let idToken: String?
        let id_token: String?
        let accountID: String?
        let accountId: String?
        let account_id: String?
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
