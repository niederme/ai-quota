import Foundation

public struct AuthToken: Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?

    public var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        // Refresh 60s before actual expiry
        return exp.addingTimeInterval(-60) < .now
    }

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

// Response from token exchange endpoint
struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }

    var asAuthToken: AuthToken {
        let expiry = expiresIn.map { Date.now.addingTimeInterval(TimeInterval($0)) }
        return AuthToken(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiry)
    }
}
