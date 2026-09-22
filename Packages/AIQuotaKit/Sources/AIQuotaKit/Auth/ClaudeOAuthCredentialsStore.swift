import Foundation
import LocalAuthentication
import Security

public struct ClaudeOAuthCredentials: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let scopes: [String]
    public let rateLimitTier: String?
    public let subscriptionType: String?

    public var hasRequiredScope: Bool {
        scopes.contains("user:profile")
    }

    public var isExpired: Bool {
        guard let expiresAt else { return true }
        return Date() >= expiresAt
    }
}

public enum ClaudeOAuthCredentialsError: LocalizedError, Sendable {
    case notFound
    case decodeFailed
    case missingOAuth
    case missingAccessToken
    case expired
    case missingScope

    public var errorDescription: String? {
        switch self {
        case .notFound:
            "Claude Code credentials not found. Run `claude` to sign in."
        case .decodeFailed:
            "Could not decode Claude Code credentials."
        case .missingOAuth:
            "Claude Code credentials do not contain Claude.ai OAuth data."
        case .missingAccessToken:
            "Claude Code credentials are missing an access token."
        case .expired:
            "Open Claude Code to refresh your session."
        case .missingScope:
            "Claude Code credentials do not include usage scope."
        }
    }
}

public struct ClaudeOAuthKeychainReader: Sendable {
    public static let claudeCodeNoninteractive = ClaudeOAuthKeychainReader {
        try readNoninteractively(service: serviceName)
    }

    private static let serviceName = "Claude Code-credentials"

    private let read: @Sendable () throws -> Data?

    public init(read: @escaping @Sendable () throws -> Data?) {
        self.read = read
    }

    func readCredentialsData() throws -> Data? {
        try read()
    }

    // LAContext only suppresses authentication for the data-protection keychain.
    // Claude Code owns a legacy login-keychain item, so guard the entire lookup
    // with the legacy interaction switch as well. Keep this synchronous and
    // serialized: the switch is process-wide, not task-local.
    static func readNoninteractively(service: String, keychain: SecKeychain? = nil) throws -> Data? {
        try LegacyKeychainInteraction.withoutUI {
            var scope: [CFString: Any] = [kSecAttrService: service]
            if let keychain { scope[kSecMatchSearchList] = [keychain] }
            if let persistentRef = try newestPersistentRef(scope: scope) {
                return try readData(persistentRef: persistentRef)
            }
            return try copyData(query: nonInteractiveQuery(scope.merging([
                kSecClass: kSecClassGenericPassword,
                kSecMatchLimit: kSecMatchLimitOne,
                kSecReturnData: true,
            ]) { _, new in new }))
        }
    }

    private static func newestPersistentRef(scope: [CFString: Any]) throws -> Data? {
        let query = nonInteractiveQuery(scope.merging([
            kSecClass: kSecClassGenericPassword,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
            kSecReturnPersistentRef: true,
        ]) { _, new in new })

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound, errSecInteractionNotAllowed, errSecUserCanceled, errSecAuthFailed:
            return nil
        default:
            throw ClaudeOAuthKeychainError(status: status)
        }

        guard let rows = result as? [[String: Any]] else { return nil }
        return newestPersistentRef(in: rows)
    }

    static func newestPersistentRef(in rows: [[String: Any]]) -> Data? {
        return rows
            .compactMap { row -> (persistentRef: Data, date: Date)? in
                guard let persistentRef = row[kSecValuePersistentRef as String] as? Data else {
                    return nil
                }
                let date = (row[kSecAttrModificationDate as String] as? Date)
                    ?? (row[kSecAttrCreationDate as String] as? Date)
                    ?? .distantPast
                return (persistentRef, date)
            }
            .max { $0.date < $1.date }?
            .persistentRef
    }

    private static func readData(persistentRef: Data) throws -> Data? {
        let query = nonInteractiveQuery([
            kSecClass: kSecClassGenericPassword,
            kSecValuePersistentRef: persistentRef,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ])
        return try copyData(query: query)
    }

    /// Claude Code owns this item, so background recovery must never ask the
    /// user to grant AIQuota access. A protected item simply falls through to
    /// AIQuota's WebKit sign-in path.
    private static func nonInteractiveQuery(_ values: [CFString: Any]) -> [CFString: Any] {
        let authContext = LAContext()
        authContext.interactionNotAllowed = true
        var query = values
        query[kSecUseAuthenticationContext] = authContext
        return query
    }

    private static func copyData(query: [CFString: Any]) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound, errSecInteractionNotAllowed, errSecUserCanceled, errSecAuthFailed:
            return nil
        default:
            throw ClaudeOAuthKeychainError(status: status)
        }
    }
}

enum LegacyKeychainInteraction {
    private static let lock = NSLock()

    static func withoutUI<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        var previouslyAllowed: DarwinBoolean = false
        let readStatus = SecKeychainGetUserInteractionAllowed(&previouslyAllowed)
        guard readStatus == errSecSuccess else { throw ClaudeOAuthKeychainError(status: readStatus) }
        let disableStatus = SecKeychainSetUserInteractionAllowed(false)
        guard disableStatus == errSecSuccess else { throw ClaudeOAuthKeychainError(status: disableStatus) }
        defer { SecKeychainSetUserInteractionAllowed(previouslyAllowed.boolValue) }
        return try operation()
    }
}

private struct ClaudeOAuthKeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String?
            ?? "Claude Code Keychain lookup failed with status \(status)."
    }
}

public enum ClaudeOAuthCredentialsStore {
    static func hasUsableCredentials(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        keychainReader: ClaudeOAuthKeychainReader? = nil
    ) -> Bool {
        (try? loadUsable(env: env, fileManager: fileManager, keychainReader: keychainReader)) != nil
    }

    static func loadUsable(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        keychainReader: ClaudeOAuthKeychainReader? = nil
    ) throws -> ClaudeOAuthCredentials {
        guard AppDistribution.allowsHostCredentialDiscovery else { throw ClaudeOAuthCredentialsError.notFound }
        let url = credentialsURL(env: env, fileManager: fileManager)
        let fileError: Error?
        if fileManager.fileExists(atPath: url.path) {
            do {
                return try validateUsable(parse(data: Data(contentsOf: url)))
            } catch {
                fileError = error
            }
        } else {
            fileError = nil
        }

        if let keychainReader {
            do {
                guard let data = try keychainReader.readCredentialsData() else {
                    throw fileError ?? ClaudeOAuthCredentialsError.notFound
                }
                return try validateUsable(parse(data: data))
            } catch {
                throw fileError ?? error
            }
        }

        if let fileError { throw fileError }
        throw ClaudeOAuthCredentialsError.notFound
    }

    private static func validateUsable(_ credentials: ClaudeOAuthCredentials) throws -> ClaudeOAuthCredentials {
        guard !credentials.isExpired else { throw ClaudeOAuthCredentialsError.expired }
        guard credentials.hasRequiredScope else { throw ClaudeOAuthCredentialsError.missingScope }
        return credentials
    }

    static func parse(data: Data) throws -> ClaudeOAuthCredentials {
        let decoder = JSONDecoder()
        guard let root = try? decoder.decode(Root.self, from: data) else {
            throw ClaudeOAuthCredentialsError.decodeFailed
        }
        guard let oauth = root.claudeAiOauth else {
            throw ClaudeOAuthCredentialsError.missingOAuth
        }
        let accessToken = oauth.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !accessToken.isEmpty else {
            throw ClaudeOAuthCredentialsError.missingAccessToken
        }
        let expiresAt = oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000.0) }
        return ClaudeOAuthCredentials(
            accessToken: accessToken,
            refreshToken: oauth.refreshToken,
            expiresAt: expiresAt,
            scopes: oauth.scopes ?? [],
            rateLimitTier: oauth.rateLimitTier,
            subscriptionType: oauth.subscriptionType
        )
    }

    static func credentialsURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let configDir = env["CLAUDE_CONFIG_DIR"]?.split(separator: ",").first {
            let path = String(configDir).trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return URL(fileURLWithPath: path).appendingPathComponent(".credentials.json")
            }
        }
        let home = env["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".claude/.credentials.json")
    }

    private struct Root: Decodable {
        let claudeAiOauth: OAuth?
    }

    private struct OAuth: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresAt: Double?
        let scopes: [String]?
        let rateLimitTier: String?
        let subscriptionType: String?
    }
}
