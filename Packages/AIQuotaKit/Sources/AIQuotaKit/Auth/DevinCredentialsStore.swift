import Foundation
import MobileAccessCore
import SQLite3

/// A Devin session credential resolved from local Devin-owned state.
/// Read-only: AIQuota never writes to Devin's files.
public struct DevinCredential: Sendable, Equatable {
    public let apiKey: String
    public let apiServerURL: URL
    public let source: DevinUsage.Source

    public init(apiKey: String, apiServerURL: URL, source: DevinUsage.Source) {
        self.apiKey = apiKey
        self.apiServerURL = apiServerURL
        self.source = source
    }
}

/// Discovers the credential Devin's own CLI and desktop app already keep on
/// this machine — the same pattern the app uses for Codex's `auth.json`.
///
/// Source order (first working wins):
/// 1. `$XDG_DATA_HOME/devin/credentials.toml` (default `~/.local/share/devin/`)
/// 2. Devin app's `state.vscdb` → `windsurfAuthStatus` → `apiKey`
/// 3. A session token the user pasted in Settings (Keychain)
public enum DevinCredentialsStore {
    private static let manualTokenKeychainKey = "devin.manualSessionToken"

    // MARK: - Resolution

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> DevinCredential? {
        candidates(environment: environment, home: home).first
    }

    /// All discoverable credentials in preference order. Callers validate each
    /// and use the first the server accepts — the CLI token may be stale while
    /// the Devin app is signed in under a working one.
    public static func candidates(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [DevinCredential] {
        [
            cliCredential(environment: environment, home: home),
            appStateCredential(home: home),
            manualCredential(),
        ].compactMap { $0 }
    }

    /// True when a host-side credential exists (CLI or desktop app), ignoring
    /// any manually pasted token.
    public static func hasDiscoverableCredential(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        cliCredential(environment: environment, home: home) != nil
            || appStateCredential(home: home) != nil
    }

    // MARK: - Devin CLI credentials.toml

    /// Only reachable from unsandboxed (direct-distribution) builds — a
    /// sandboxed process simply gets nil from the file reads.
    public static func cliCredential(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> DevinCredential? {
        for file in credentialsFileCandidates(environment: environment, home: home) {
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  let parsed = CredentialsFile.parse(text)
            else { continue }
            return DevinCredential(
                apiKey: parsed.apiKey,
                apiServerURL: parsed.apiServerURL ?? DevinAPI.defaultAPIServerURL,
                source: .cli
            )
        }
        return nil
    }

    static func credentialsFileCandidates(
        environment: [String: String],
        home: URL
    ) -> [URL] {
        var candidates: [URL] = []
        if let xdg = environment["XDG_DATA_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !xdg.isEmpty {
            candidates.append(URL(fileURLWithPath: xdg, isDirectory: true)
                .appendingPathComponent("devin/credentials.toml"))
        }
        candidates.append(home.appendingPathComponent(".local/share/devin/credentials.toml"))
        return candidates
    }

    // MARK: - Devin app state.vscdb

    public static func appStateCredential(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> DevinCredential? {
        let dbPath = home.appendingPathComponent(
            "Library/Application Support/Devin/User/globalStorage/state.vscdb"
        )
        guard let apiKey = readAuthStatusAPIKey(dbPath: dbPath.path) else { return nil }
        return DevinCredential(
            apiKey: apiKey,
            apiServerURL: DevinAPI.defaultAPIServerURL,
            source: .appState
        )
    }

    /// Reads `windsurfAuthStatus` from the Devin app's VS Code-style state db.
    /// Opens read-only and never writes.
    static func readAuthStatusAPIKey(dbPath: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = 'windsurfAuthStatus'"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0)
        else { return nil }

        let json = String(cString: cString)
        struct AuthStatus: Decodable { let apiKey: String? }
        guard let status = try? JSONDecoder().decode(AuthStatus.self, from: Data(json.utf8)),
              let apiKey = status.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty
        else { return nil }
        return apiKey
    }

    // MARK: - Manual token

    /// Session tokens pasted into Settings are stored in the app's own
    /// data-protection keychain — never in Devin's files or UserDefaults.
    public static func saveManualToken(_ token: String) {
        KeychainStore.save(token, forKey: manualTokenKeychainKey)
    }

    public static func manualCredential() -> DevinCredential? {
        guard let token = KeychainStore.load(forKey: manualTokenKeychainKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else { return nil }
        return DevinCredential(
            apiKey: token,
            apiServerURL: DevinAPI.defaultAPIServerURL,
            source: .manual
        )
    }

    public static func clearManualToken() {
        KeychainStore.delete(forKey: manualTokenKeychainKey)
    }

    // MARK: - credentials.toml parsing

    /// Minimal parser for the two keys AIQuota needs. Devin's credentials.toml
    /// is flat `[section]`-less TOML written by `devin auth login`; a full TOML
    /// dependency is not warranted here.
    public struct CredentialsFile: Sendable, Equatable {
        public let apiKey: String
        public let apiServerURL: URL?

        public static func parse(_ text: String) -> CredentialsFile? {
            var apiKey: String?
            var serverURL: URL?

            for rawLine in text.split(separator: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#") else { continue }
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                var value = parts[1].trimmingCharacters(in: .whitespaces)
                // Quoted value: cut at the closing quote so trailing comments
                // don't leak into the credential.
                if let quote = value.first, quote == "\"" || quote == "'" {
                    let rest = value.dropFirst()
                    if let end = rest.firstIndex(of: quote) {
                        value = String(rest[..<end])
                    }
                }
                switch key {
                case "windsurf_api_key":
                    apiKey = value
                case "api_server_url":
                    serverURL = URL(string: value)
                default:
                    continue
                }
            }

            guard let apiKey, !apiKey.isEmpty else { return nil }
            return CredentialsFile(apiKey: apiKey, apiServerURL: serverURL)
        }
    }
}
