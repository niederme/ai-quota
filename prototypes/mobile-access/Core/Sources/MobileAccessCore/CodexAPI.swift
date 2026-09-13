import Foundation

public enum AccessError: Error, LocalizedError, Sendable, Equatable {
    case http(Int), invalidResponse, noWindows, expired, storage
    public var errorDescription: String? {
        switch self {
        case .http(let status): "Provider request failed (HTTP \(status))."
        case .invalidResponse: "The provider returned an unexpected response."
        case .noWindows: "This account did not report a supported quota window."
        case .expired: "Sign-in expired. Start a new connection."
        case .storage: "The connection could not be saved securely."
        }
    }
}

public struct HTTPResult: Sendable {
    public let data: Data
    public let status: Int
    public init(data: Data, status: Int) { self.data = data; self.status = status }
}
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResult
}
public struct ProviderTransport: HTTPTransport {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpShouldSetCookies = false
        config.urlCache = nil
        session = URLSession(configuration: config)
    }
    public func send(_ request: URLRequest) async throws -> HTTPResult {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccessError.invalidResponse }
        return HTTPResult(data: data, status: http.statusCode)
    }
}

public struct DeviceChallenge: Decodable, Sendable {
    public let deviceAuthID: String
    public let userCode: String
    public let interval: Double
    public var verificationURL: URL { URL(string: "https://auth.openai.com/codex/device")! }
    enum CodingKeys: String, CodingKey { case deviceAuthID = "device_auth_id", userCode = "user_code", usercode, interval }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceAuthID = try c.decode(String.self, forKey: .deviceAuthID)
        userCode = try c.decodeIfPresent(String.self, forKey: .userCode) ?? c.decode(String.self, forKey: .usercode)
        let number = try? c.decode(Double.self, forKey: .interval)
        let string = try? c.decode(String.self, forKey: .interval)
        interval = max(5, number ?? string.flatMap(Double.init) ?? 5)
        guard !deviceAuthID.isEmpty, !userCode.isEmpty, interval.isFinite, interval <= 900 else {
            throw AccessError.invalidResponse
        }
    }
}
public struct AuthorizationCode: Decodable, Sendable {
    public let code: String
    public let verifier: String
    enum CodingKeys: String, CodingKey { case code = "authorization_code", verifier = "code_verifier" }
}
public struct CodexTokens: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let accountID: String?
    public let expiresAt: Date
    public func needsRefresh(at date: Date) -> Bool { expiresAt <= date.addingTimeInterval(60) }
}
public struct QuotaWindow: Codable, Sendable, Equatable {
    public let usedPercent: Double
    public let durationSeconds: Int
    public let resetsAt: Date?
    public var label: String {
        durationSeconds >= 6 * 86400 ? "Weekly" : "\(durationSeconds / 3600) hours"
    }
}
public struct QuotaReading: Codable, Sendable, Equatable {
    public let fetchedAt: Date
    public let shortTerm: QuotaWindow?
    public let weekly: QuotaWindow?
    public let metadata: AccountMetadata?
    public init(fetchedAt: Date, shortTerm: QuotaWindow?, weekly: QuotaWindow?, metadata: AccountMetadata? = nil) {
        self.fetchedAt = fetchedAt; self.shortTerm = shortTerm; self.weekly = weekly; self.metadata = metadata
    }
    public static func decode(_ data: Data, now: Date) throws -> Self {
        let raw = try JSONDecoder().decode(UsageResponse.self, from: data)
        let windows = [raw.rateLimit?.primary, raw.rateLimit?.secondary].compactMap { $0 }
        func convert(_ w: UsageWindow) throws -> QuotaWindow {
            guard w.used.isFinite, (0...100).contains(w.used), w.seconds > 0 else { throw AccessError.invalidResponse }
            return QuotaWindow(usedPercent: w.used, durationSeconds: w.seconds,
                               resetsAt: w.reset.map { Date(timeIntervalSince1970: $0) })
        }
        let parsed = try windows.map(convert)
        let short = parsed.first { $0.durationSeconds < 6 * 86400 }
        let week = parsed.first { $0.durationSeconds >= 6 * 86400 }
        guard short != nil || week != nil else { throw AccessError.noWindows }
        let balance = raw.credits?.balance?.value
        let metadata = AccountMetadata(plan: raw.planType, balanceUSD: balance.map { $0 / 25 }, usageSpent: nil, usageCurrency: nil)
        return Self(fetchedAt: now, shortTerm: short, weekly: week, metadata: metadata)
    }
}
private struct UsageResponse: Decodable {
    let rateLimit: UsageLimit?
    let planType: String?
    let credits: Credits?
    struct Credits: Decodable { let balance: MetadataNumber? }
    enum CodingKeys: String, CodingKey { case rateLimit = "rate_limit", planType = "plan_type", credits }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rateLimit = try c.decodeIfPresent(UsageLimit.self, forKey: .rateLimit)
        planType = try? c.decode(String.self, forKey: .planType)
        credits = try? c.decode(Credits.self, forKey: .credits)
    }
}
private struct UsageLimit: Decodable {
    let primary: UsageWindow?
    let secondary: UsageWindow?
    enum CodingKeys: String, CodingKey { case primary = "primary_window", secondary = "secondary_window" }
}
private struct UsageWindow: Decodable {
    let used: Double
    let seconds: Int
    let reset: Double?
    enum CodingKeys: String, CodingKey { case used = "used_percent", seconds = "limit_window_seconds", reset = "reset_at" }
}

public struct CodexAPI: Sendable {
    // Public first-party Codex CLI client identifier, not an AI Quota client registration.
    // Personal feasibility probe only. Distribution authorization remains unresolved.
    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = ProviderTransport()) { self.transport = transport }
    public func requestChallenge() async throws -> DeviceChallenge {
        let r = try await postJSON("https://auth.openai.com/api/accounts/deviceauth/usercode", ["client_id": Self.clientID])
        try validate(r)
        return try JSONDecoder().decode(DeviceChallenge.self, from: r.data)
    }
    /// nil is pending per the first-party Codex device-auth implementation, not a failed connection.
    public func poll(_ challenge: DeviceChallenge) async throws -> AuthorizationCode? {
        let r = try await postJSON("https://auth.openai.com/api/accounts/deviceauth/token",
                                   ["device_auth_id": challenge.deviceAuthID, "user_code": challenge.userCode])
        if r.status == 403 || r.status == 404 { return nil }
        try validate(r)
        return try JSONDecoder().decode(AuthorizationCode.self, from: r.data)
    }
    public func exchange(_ code: AuthorizationCode, now: Date = .now) async throws -> CodexTokens {
        guard !code.code.isEmpty, !code.verifier.isEmpty else { throw AccessError.invalidResponse }
        return try await tokenRequest(["grant_type": "authorization_code", "code": code.code,
            "code_verifier": code.verifier, "redirect_uri": "https://auth.openai.com/deviceauth/callback",
            "client_id": Self.clientID], previous: nil, now: now)
    }
    public func renew(_ tokens: CodexTokens, now: Date = .now) async throws -> CodexTokens {
        guard let refresh = tokens.refreshToken, !refresh.isEmpty else { throw AccessError.expired }
        return try await tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh,
            "client_id": Self.clientID], previous: tokens, now: now)
    }
    public func usage(_ tokens: CodexTokens, now: Date? = nil, includeSpending: Bool = false) async throws -> QuotaReading {
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(tokens.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://chatgpt.com/codex/settings/usage", forHTTPHeaderField: "Referer")
        let r = try await transport.send(req)
        try validate(r)
        let reading = try QuotaReading.decode(r.data, now: now ?? .now)
        guard includeSpending else { return reading }
        req.url = URL(string: "https://chatgpt.com/backend-api/wham/usage/credit-usage-events")!
        req.timeoutInterval = 5
        // Optional metadata must not turn a successful quota fetch into a failure.
        guard let response = try? await transport.send(req), (200..<300).contains(response.status),
              let spent = try? Self.decodeSpending(response.data, now: reading.fetchedAt) else { return reading }
        return QuotaReading(fetchedAt: reading.fetchedAt, shortTerm: reading.shortTerm, weekly: reading.weekly,
            metadata: AccountMetadata(plan: reading.metadata?.plan, balanceUSD: reading.metadata?.balanceUSD,
                usageSpent: spent, usageCurrency: "USD"))
    }
    public static func decodeSpending(_ data: Data, now: Date, calendar: Calendar = .current) throws -> Double {
        struct Events: Decodable {
            struct Event: Decodable { let date: String; let credit_amount: Double }
            let data: [Event]
        }
        let events = try JSONDecoder().decode(Events.self, from: data)
        guard let interval = calendar.dateInterval(of: .month, for: now) else { throw AccessError.invalidResponse }
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        var total = 0.0
        for event in events.data {
            guard event.credit_amount.isFinite, event.credit_amount >= 0,
                  let date = formatter.date(from: event.date) else { throw AccessError.invalidResponse }
            if interval.contains(date) { total += event.credit_amount }
        }
        guard total.isFinite else { throw AccessError.invalidResponse }
        return total / 25
    }
    private func tokenRequest(_ values: [String: String], previous: CodexTokens?, now: Date) async throws -> CodexTokens {
        var req = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formBody(values)
        let r = try await transport.send(req)
        try validate(r)
        let raw = try JSONDecoder().decode(TokenResponse.self, from: r.data)
        guard !raw.access.isEmpty else { throw AccessError.invalidResponse }
        // JWT claims are routing/expiry hints only, never proof of authentication.
        let claims = Self.claims(raw.id ?? raw.access)
        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        let accountID = auth?["chatgpt_account_id"] as? String ?? previous?.accountID
        let accessClaims = Self.claims(raw.access)
        let expiry = raw.expires.map { now.addingTimeInterval($0) }
            ?? (accessClaims["exp"] as? Double).map { Date(timeIntervalSince1970: $0) }
            ?? now.addingTimeInterval(300)
        guard expiry > now else { throw AccessError.expired }
        return CodexTokens(accessToken: raw.access, refreshToken: raw.refresh ?? previous?.refreshToken,
                           accountID: accountID, expiresAt: expiry)
    }
    public static func formBody(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = values.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
    private static func claims(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return [:] }
        var text = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let data = Data(base64Encoded: text), let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return result
    }
    private func postJSON(_ url: String, _ values: [String: String]) async throws -> HTTPResult {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(values)
        return try await transport.send(req)
    }
    private func validate(_ response: HTTPResult) throws {
        guard (200..<300).contains(response.status) else { throw AccessError.http(response.status) }
    }
}
private struct TokenResponse: Decodable {
    let access: String
    let refresh: String?
    let id: String?
    let expires: Double?
    enum CodingKeys: String, CodingKey {
        case access = "access_token", refresh = "refresh_token", id = "id_token", expires = "expires_in"
    }
}
