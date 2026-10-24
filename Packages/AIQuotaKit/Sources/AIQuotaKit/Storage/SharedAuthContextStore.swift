import Foundation
import Darwin

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
    public let accountID: String?

    public init(sessionToken: String, accessToken: String?, accessTokenExpiresAt: Date?, accountID: String? = nil) {
        self.sessionToken = sessionToken
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.accountID = accountID
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

/// Credential snapshots used by the widget extension for best-effort background
/// refresh. The app's auth coordinators must not treat these snapshots as a
/// login source; app authentication comes from live OAuth credentials or WebKit.
public enum SharedAuthContextStore {
    private static let codexKey = "sharedCodexAuthContext"
    private static let claudeKey = "sharedClaudeAuthContext"

    public static func loadCodex() -> SharedCodexAuthContext? {
        KeychainStore.load(SharedCodexAuthContext.self, forKey: codexKey, decoder: decoder)
    }

    public static func saveCodex(_ context: SharedCodexAuthContext) {
        withSingletonLock { KeychainStore.save(context, forKey: codexKey, encoder: encoder) }
    }

    public static func clearCodex() {
        withSingletonLock { KeychainStore.delete(forKey: codexKey) }
    }

    public static func loadCodex(forAccountID accountID: String) -> SharedCodexAuthContext? {
        KeychainStore.load(SharedCodexAuthContext.self, forKey: accountKey(codexKey, accountID: accountID), decoder: decoder)
    }

    public static func saveCodex(_ context: SharedCodexAuthContext, forAccountID accountID: String) {
        KeychainStore.save(context, forKey: accountKey(codexKey, accountID: accountID), encoder: encoder)
    }

    public static func clearCodex(forAccountID accountID: String) {
        KeychainStore.delete(forKey: accountKey(codexKey, accountID: accountID))
    }

    public static func loadClaude() -> SharedClaudeAuthContext? {
        KeychainStore.load(SharedClaudeAuthContext.self, forKey: claudeKey, decoder: decoder)
    }

    public static func saveClaude(orgId: String, cookies: [HTTPCookie]) {
        let context = SharedClaudeAuthContext(orgId: orgId, cookies: cookies.map(PersistedCookie.init))
        withSingletonLock { KeychainStore.save(context, forKey: claudeKey, encoder: encoder) }
    }

    public static func clearClaude() {
        withSingletonLock { KeychainStore.delete(forKey: claudeKey) }
    }

    public static func loadClaude(forAccountID accountID: String) -> SharedClaudeAuthContext? {
        KeychainStore.load(SharedClaudeAuthContext.self, forKey: accountKey(claudeKey, accountID: accountID), decoder: decoder)
    }

    public static func saveClaude(orgId: String, cookies: [HTTPCookie], forAccountID accountID: String) {
        let context = SharedClaudeAuthContext(orgId: orgId, cookies: cookies.map(PersistedCookie.init))
        saveClaude(context, forAccountID: accountID)
    }

    public static func saveClaude(_ context: SharedClaudeAuthContext, forAccountID accountID: String) {
        KeychainStore.save(context, forKey: accountKey(claudeKey, accountID: accountID), encoder: encoder)
    }

    public static func clearClaude(forAccountID accountID: String) {
        KeychainStore.delete(forKey: accountKey(claudeKey, accountID: accountID))
    }

    // The app and widget are different processes. Compare-and-write must hold
    // the same short lease as singleton credential replacement/removal, with no
    // network await inside it. A process-local actor/lock cannot enforce this.
    @discardableResult
    private static func withSingletonLock<T>(_ body: () -> T) -> T? {
        let container: URL
        if Bundle.allBundles.contains(where: { $0.bundlePath.hasSuffix(".xctest") }) {
            // Existing package tests use a process-specific Keychain service and
            // defaults suite. Their lock must not require a signed app-group host.
            container = FileManager.default.temporaryDirectory
                .appendingPathComponent("aiquota-auth-lock.tests.\(ProcessInfo.processInfo.processIdentifier)")
            guard (try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)) != nil else { return nil }
        } else {
            guard let group = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.niederme.AIQuota"
            ) else { return nil }
            container = group
        }
        let fd = open(container.appendingPathComponent("auth-context.lock").path,
                      O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            if errno != EINTR { return nil }
        }
        defer { flock(fd, LOCK_UN) }
        return body()
    }

    static func commitCodexRefresh(expected: SharedCodexAuthContext,
                                   renewed: SharedCodexAuthContext?, usage: CodexUsage?) -> Bool {
        withSingletonLock {
            guard loadCodex() == expected else { return false }
            if let renewed { KeychainStore.save(renewed, forKey: codexKey, encoder: encoder) }
            if let usage { SharedDefaults.saveUsage(usage) }
            return true
        } ?? false
    }

    static func clearCodex(ifCurrent expected: SharedCodexAuthContext) {
        withSingletonLock {
            guard loadCodex() == expected else { return }
            KeychainStore.delete(forKey: codexKey)
            SharedDefaults.clearUsage()
        }
    }

    static func commitClaudeRefresh(expected: SharedClaudeAuthContext, usage: ClaudeUsage) -> Bool {
        withSingletonLock {
            guard loadClaude() == expected else { return false }
            SharedDefaults.saveClaudeUsage(usage)
            return true
        } ?? false
    }

    static func clearClaude(ifCurrent expected: SharedClaudeAuthContext) {
        withSingletonLock {
            guard loadClaude() == expected else { return }
            KeychainStore.delete(forKey: claudeKey)
            SharedDefaults.clearClaudeUsage()
        }
    }

    private static func accountKey(_ base: String, accountID: String) -> String {
        "\(base).account.\(accountID)"
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
