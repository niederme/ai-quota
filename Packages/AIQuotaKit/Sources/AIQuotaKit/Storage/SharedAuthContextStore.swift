import Foundation

public struct PersistedCookie: Codable, Sendable, Equatable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let expiresAt: Date?
    public let isSecure: Bool

    public init(_ cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.expiresAt = cookie.expiresDate
        self.isSecure = cookie.isSecure
    }

    public var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .path: path,
            .name: name,
            .value: value,
        ]
        if let expiresAt {
            properties[.expires] = expiresAt
        }
        if isSecure {
            properties[.secure] = true
        }
        return HTTPCookie(properties: properties)
    }
}

public struct SharedCodexAuthContext: Codable, Sendable, Equatable {
    public let sessionToken: String
    public let accessToken: String?
    public let accessTokenExpiresAt: Date?

    public init(sessionToken: String, accessToken: String?, accessTokenExpiresAt: Date?) {
        self.sessionToken = sessionToken
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }

    public func hasUsableAccessToken(at date: Date = .now) -> Bool {
        guard let accessToken, !accessToken.isEmpty,
              let accessTokenExpiresAt
        else { return false }
        return accessTokenExpiresAt.addingTimeInterval(-60) > date
    }
}

public struct SharedClaudeAuthContext: Codable, Sendable, Equatable {
    public let orgId: String
    public let cookies: [PersistedCookie]

    public init(orgId: String, cookies: [PersistedCookie]) {
        self.orgId = orgId
        self.cookies = cookies
    }

    public var httpCookies: [HTTPCookie] {
        cookies.compactMap(\.httpCookie)
    }
}

public enum SharedAuthContextStore {
    private static let codexKey = "sharedCodexAuthContext"
    private static let claudeKey = "sharedClaudeAuthContext"

    public static func loadCodex() -> SharedCodexAuthContext? {
        KeychainStore.load(SharedCodexAuthContext.self, forKey: codexKey, decoder: decoder)
    }

    public static func saveCodex(_ context: SharedCodexAuthContext) {
        KeychainStore.save(context, forKey: codexKey, encoder: encoder)
    }

    public static func clearCodex() {
        KeychainStore.delete(forKey: codexKey)
    }

    public static func loadClaude() -> SharedClaudeAuthContext? {
        KeychainStore.load(SharedClaudeAuthContext.self, forKey: claudeKey, decoder: decoder)
    }

    public static func saveClaude(orgId: String, cookies: [HTTPCookie]) {
        let context = SharedClaudeAuthContext(orgId: orgId, cookies: cookies.map(PersistedCookie.init))
        KeychainStore.save(context, forKey: claudeKey, encoder: encoder)
    }

    public static func clearClaude() {
        KeychainStore.delete(forKey: claudeKey)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
