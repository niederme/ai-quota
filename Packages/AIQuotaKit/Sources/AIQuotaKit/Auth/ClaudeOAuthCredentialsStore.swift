import Foundation

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

public enum ClaudeOAuthCredentialsStore {
    public static func hasUsableCredentials(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        keychainReader: ClaudeOAuthKeychainReader? = .claudeCodeSecurityCLI
    ) -> Bool {
        (try? loadUsable(env: env, fileManager: fileManager, keychainReader: keychainReader)) != nil
    }

    public static func loadUsable(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        keychainReader: ClaudeOAuthKeychainReader? = .claudeCodeSecurityCLI
    ) throws -> ClaudeOAuthCredentials {
        let credentials = try load(env: env, fileManager: fileManager, keychainReader: keychainReader)
        guard !credentials.isExpired else { throw ClaudeOAuthCredentialsError.expired }
        guard credentials.hasRequiredScope else { throw ClaudeOAuthCredentialsError.missingScope }
        return credentials
    }

    public static func load(
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

    public static func parse(data: Data) throws -> ClaudeOAuthCredentials {
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

    public static func credentialsURL(
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
