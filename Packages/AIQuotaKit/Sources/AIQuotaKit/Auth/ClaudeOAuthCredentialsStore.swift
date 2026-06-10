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
    public static let claudeCodeInteractive = ClaudeOAuthKeychainReader {
        try readClaudeCodeSecurityFramework()
    }

    public static let claudeCodeSecurityCLI = ClaudeOAuthKeychainReader {
        try readClaudeCodeSecurityCLI()
    }

    private static let serviceName = "Claude Code-credentials"
    private static let timeout: DispatchTimeInterval = .milliseconds(1500)

    private let read: @Sendable () throws -> Data?

    public init(read: @escaping @Sendable () throws -> Data?) {
        self.read = read
    }

    func readCredentialsData() throws -> Data? {
        try read()
    }

    private static func readClaudeCodeSecurityFramework() throws -> Data? {
        if let persistentRef = try newestClaudeCodePersistentRef() {
            return try readData(persistentRef: persistentRef)
        }
        return try readData(service: serviceName)
    }

    private static func newestClaudeCodePersistentRef() throws -> Data? {
        let authContext = LAContext()
        authContext.interactionNotAllowed = true
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
            kSecReturnPersistentRef: true,
            kSecUseAuthenticationContext: authContext,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound, errSecInteractionNotAllowed:
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
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecValuePersistentRef: persistentRef,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]
        return try copyData(query: query)
    }

    private static func readData(service: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]
        return try copyData(query: query)
    }

    private static func copyData(query: [CFString: Any]) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound, errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            return nil
        default:
            throw ClaudeOAuthKeychainError(status: status)
        }
    }

    private static func readClaudeCodeSecurityCLI() throws -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", serviceName,
            "-w"
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        try process.run()

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }

        guard group.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            return nil
        }
        return Data(text.utf8)
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
        keychainReader: ClaudeOAuthKeychainReader? = .claudeCodeSecurityCLI
    ) -> Bool {
        (try? loadUsable(env: env, fileManager: fileManager, keychainReader: keychainReader)) != nil
    }

    static func loadUsable(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        keychainReader: ClaudeOAuthKeychainReader? = .claudeCodeSecurityCLI
    ) throws -> ClaudeOAuthCredentials {
        let credentials = try load(env: env, fileManager: fileManager, keychainReader: keychainReader)
        guard !credentials.isExpired else { throw ClaudeOAuthCredentialsError.expired }
        guard credentials.hasRequiredScope else { throw ClaudeOAuthCredentialsError.missingScope }
        return credentials
    }

    static func load(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        keychainReader: ClaudeOAuthKeychainReader? = .claudeCodeSecurityCLI
    ) throws -> ClaudeOAuthCredentials {
        let url = credentialsURL(env: env, fileManager: fileManager)
        if fileManager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            return try parse(data: data)
        }

        if let keychainReader, let data = try? keychainReader.readCredentialsData() {
            return try parse(data: data)
        }

        throw ClaudeOAuthCredentialsError.notFound
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
